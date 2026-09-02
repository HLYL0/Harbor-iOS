import Foundation

// MARK: - Watch Together protocol core (Phase 18, audit casting-together.md §2).
// Pure client-side logic ported with EXACT Harbor constants: room codes, sync
// drift decisions, clock correction (EMA offset), seek coalescing, source matching.
// The relay stays external (wss://pub.harbor.site or user-deployed Cloudflare relay).

enum TogetherProtocol {

    // Version gates (Harbor, audit §2.2).
    static let wtProtocol = 2
    static let requiredRelayVersion = 10

    // Room codes (protocol.ts:149-164): alphabet without 0/1/I/O, 6 chars.
    static let roomCodeAlphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    // Sync constants (player-utils.ts / use-room-sync.ts).
    static let hostHeartbeatMs = 1000
    static let syncPlayLookaheadSeconds = 0.4
    static let syncMaxAgeSeconds = 30.0
    static let syncDriftToleranceSeconds = 0.6
    static let syncSeekJumpSeconds = 10.0
    static let syncSuppressMs = 1400
    static let seekCoalesceMs = 250
    static let seekApplyDebounceMs = 120
    static let readyStaleMs = 20_000
    static let guestEscapeMs = 45_000
    static let roomIdleMs = 6 * 3600 * 1000   // 6 h
    static let pingIntervalMs = 25_000
    static let rttDiscardMs = 10_000
    static let clockOffsetEmaAlpha = 0.3      // offset = 0.7*offset + 0.3*sample
    static let inviteWindowMs = 60_000
    static let chatCap = 500
    static let chatLocalHistory = 200
    static let cursorSendIntervalMs = 60
    static let cursorIdleMs = 1500
    static let cursorExpireMs = 6000
    static let drawStrokeGcMs = 9500

    // MARK: - Room codes

    static func generateRoomCode() -> String {
        var code = ""
        for _ in 0..<6 {
            code.append(roomCodeAlphabet.randomElement()!)
        }
        return code
    }

    static func normalizeRoomCode(_ raw: String) -> String? {
        let cleaned = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard cleaned.count >= 4, cleaned.count <= 8 else { return nil }
        return cleaned
    }

    // MARK: - Clock correction (client.ts:565-610)

    /// EMA offset estimation. First sample seeds; then offset = 0.7*offset + 0.3*sample.
    /// sample = srvAt − (pingSentAt + rtt/2).
    static func clockSample(pingSentAtMs: Int64, srvAtMs: Int64, rttMs: Int64) -> Int64? {
        guard rttMs < rttDiscardMs else { return nil }
        return srvAtMs - (pingSentAtMs + rttMs / 2)
    }

    static func emaOffset(current: Int64?, sample: Int64) -> Int64 {
        guard let current else { return sample }
        let alpha = 0.3
        return Int64((0.7 * Double(current)) + (alpha * Double(sample)))
    }

    /// Localize a relay timestamp: updatedAt = srvAt − relayOffset.
    static func localizeClock(srvAtMs: Int64, relayOffsetMs: Int64) -> Int64 {
        srvAtMs - relayOffsetMs
    }

    // MARK: - Drift decisions (use-room-sync.ts:190-242)

    struct ApplyDecision: Equatable {
        var shouldAct: Bool
        var targetPosition: Double
        var reason: String
    }

    /// Guest apply logic: skip own echoes + out-of-order states; extrapolate target
    /// position with lookahead; act only when play-state changed or drift > 0.6s.
    static func decideApply(
        remotePosition: Double,
        remotePlaying: Bool,
        remoteUpdatedAtLocalMs: Int64,
        localNowMs: Int64,
        lastAppliedMs: Int64?,
        ownClientId: String,
        updatedBy: String,
        localPlaying: Bool
    ) -> ApplyDecision {
        if updatedBy == ownClientId {
            return ApplyDecision(shouldAct: false, targetPosition: remotePosition, reason: "own-echo")
        }
        if let lastAppliedMs, remoteUpdatedAtLocalMs < lastAppliedMs {
            return ApplyDecision(shouldAct: false, targetPosition: remotePosition, reason: "out-of-order")
        }
        let ageSeconds = min(max(Double(localNowMs - remoteUpdatedAtLocalMs) / 1000, 0), syncMaxAgeSeconds)
        let lookahead = remotePlaying ? syncPlayLookaheadSeconds : 0
        let target = remotePosition + ageSeconds + lookahead
        let drift = abs(target - remotePosition) > 0 ? target - remotePosition : 0
        // Play-state change always acts; otherwise only beyond tolerance.
        let playStateChanged = remotePlaying != localPlaying
        if playStateChanged || abs(drift) > syncDriftToleranceSeconds {
            return ApplyDecision(shouldAct: true, targetPosition: target, reason: playStateChanged ? "play-state" : "drift")
        }
        return ApplyDecision(shouldAct: false, targetPosition: target, reason: "tolerated")
    }

    /// Catch-up gate: after a corrective seek stay tolerant until drift < 10s (or buffering).
    static func withinCatchupJump(remotePosition: Double, localPosition: Double) -> Bool {
        abs(remotePosition - localPosition) >= syncSeekJumpSeconds
    }

    // MARK: - Seek coalescing (seek-coalesce.ts)

    /// Seeks within 250ms collapse; stale sequence numbers are ignored.
    static func shouldSendSeek(lastSeekSentAtMs: Int64?, nowMs: Int64) -> Bool {
        guard let lastSeekSentAtMs else { return true }
        return nowMs - lastSeekSentAtMs >= seekCoalesceMs
    }

    static func isStaleSeek(sequence: Int64, lastAppliedSequence: Int64) -> Bool {
        sequence <= lastAppliedSequence
    }

    // MARK: - Source matching (source-match.ts)

    struct SourceMatch: Equatable {
        var score: Int
        var badge: Badge

        enum Badge: String, Equatable {
            case same, close, none
        }

        static let sameThreshold = 1000
        static let closeThreshold = 300
    }

    /// Guests re-rank their streams toward the host's file:
    /// infoHash match 1000, resolution 200, size-drift 150, title Jaccard 120, group 40.
    static func matchSource(
        candidate: (infoHash: String?, resolution: String?, sizeBytes: Int64?, title: String?, releaseGroup: String?),
        host: (infoHash: String?, resolution: String?, sizeBytes: Int64?, title: String?, releaseGroup: String?)
    ) -> SourceMatch {
        var score = 0
        if let candidateHash = candidate.infoHash, let hostHash = host.infoHash,
           candidateHash.lowercased() == hostHash.lowercased() {
            score += 1000
        }
        if let candidateResolution = candidate.resolution, let hostResolution = host.resolution,
           candidateResolution == hostResolution {
            score += 200
        }
        if let candidateSize = candidate.sizeBytes, let hostSize = host.sizeBytes, hostSize > 0 {
            let drift = Double(abs(candidateSize - hostSize)) / Double(hostSize)
            if drift < 0.1 { score += 150 }
        }
        if let candidateTitle = candidate.title, let hostTitle = host.title {
            let candidateTokens = Set(candidateTitle.lowercased().split(separator: " "))
            let hostTokens = Set(hostTitle.lowercased().split(separator: " "))
            if !candidateTokens.isEmpty, !hostTokens.isEmpty {
                let intersection = candidateTokens.intersection(hostTokens).count
                let union = candidateTokens.union(hostTokens).count
                let jaccard = Double(intersection) / Double(union)
                score += Int(jaccard * 120)
            }
        }
        if let candidateGroup = candidate.releaseGroup, let hostGroup = host.releaseGroup,
           candidateGroup == hostGroup {
            score += 40
        }
        let badge: SourceMatch.Badge = score >= SourceMatch.sameThreshold ? .same : (score >= SourceMatch.closeThreshold ? .close : .none)
        return SourceMatch(score: score, badge: badge)
    }

    // MARK: - Invite link parsing (invite.ts:11-35)

    struct Invite: Equatable {
        var relay: String
        var room: String
        var proto: Int

        init?(relay: String, room: String, proto: Int = wtProtocol) {
            guard relay.hasPrefix("wss://"),
                  let normalized = normalizeRoomCode(room) else { return nil }
            self.relay = relay
            self.room = normalized
            self.proto = proto
        }
    }

    static func parseInvite(url: URL) -> Invite? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let relay = components.queryItems?.first(where: { $0.name == "harbor-relay" })?.value,
              let room = components.queryItems?.first(where: { $0.name == "harbor-room" })?.value else {
            return nil
        }
        return Invite(relay: relay, room: room)
    }

    // MARK: - Message models (protocol.ts, sanitized client-side before send)

    struct EpisodeRef: Codable, Equatable, Sendable {
        var season: Int
        var episode: Int

        init(season: Int, episode: Int) {
            self.season = season
            self.episode = episode
        }
    }

    struct SyncState: Codable, Equatable, Sendable {
        var mediaId: String?
        var mediaTitle: String?
        var episode: EpisodeRef?
        var posterUrl: String?
        var positionSeconds: Double
        var playing: Bool
        var speed: Double
        var source: String?
        var guestPick: Bool
        var updatedAtMs: Int64
        var updatedBy: String
        var hostClientId: String?
    }

    struct SourceDescriptor: Equatable, Sendable {
        var title: String
        var resolution: String
        var sizeBytes: Int64
        var infoHash: String
        var fileIdx: Int
        var durationSec: Double
    }
}
