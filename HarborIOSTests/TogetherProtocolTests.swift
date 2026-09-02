import XCTest
@testable import HarborIOS

// MARK: - Phase 18 Watch Together protocol tests (Harbor constants, audit §2).

final class TogetherProtocolTests: XCTestCase {

    func testRoomCodeGeneration() {
        for _ in 0..<50 {
            let code = TogetherProtocol.generateRoomCode()
            XCTAssertEqual(code.count, 6)
            XCTAssertTrue(code.allSatisfy { "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".contains($0) }, "invalid char in \(code)")
        }
    }

    func testRoomCodeNormalization() {
        XCTAssertEqual(TogetherProtocol.normalizeRoomCode("abc123"), "ABC123")
        XCTAssertEqual(TogetherProtocol.normalizeRoomCode(" a!b@c#1$2%3 "), "ABC123")
        XCTAssertNil(TogetherProtocol.normalizeRoomCode("AB"))
        XCTAssertNil(TogetherProtocol.normalizeRoomCode("ABCDEFGHI"))
    }

    func testClockEmaOffset() {
        // First sample seeds.
        var offset = TogetherProtocol.emaOffset(current: nil, sample: 1000)
        XCTAssertEqual(offset, 1000)
        // Subsequent samples: 0.7*old + 0.3*sample.
        offset = TogetherProtocol.emaOffset(current: offset, sample: 0)
        XCTAssertEqual(offset, 700)
        offset = TogetherProtocol.emaOffset(current: offset, sample: 200)
        XCTAssertEqual(offset, 550)   // 0.7*700 + 0.3*200
    }

    func testRTTDiscard() {
        XCTAssertNil(TogetherProtocol.clockSample(pingSentAtMs: 1000, srvAtMs: 2000, rttMs: 15_000))
        XCTAssertEqual(TogetherProtocol.clockSample(pingSentAtMs: 1000, srvAtMs: 2000, rttMs: 100), 950)
    }

    func testDriftDecisions() {
        // Own echo suppressed.
        let echo = TogetherProtocol.decideApply(
            remotePosition: 50, remotePlaying: true, remoteUpdatedAtLocalMs: 5000, localNowMs: 6000,
            lastAppliedMs: nil, ownClientId: "me", updatedBy: "me", localPlaying: true
        )
        XCTAssertFalse(echo.shouldAct)

        // Out-of-order suppressed.
        let stale = TogetherProtocol.decideApply(
            remotePosition: 50, remotePlaying: true, remoteUpdatedAtLocalMs: 4000, localNowMs: 6000,
            lastAppliedMs: 4500, ownClientId: "me", updatedBy: "host", localPlaying: true
        )
        XCTAssertFalse(stale.shouldAct)

        // Small drift tolerated.
        let tolerated = TogetherProtocol.decideApply(
            remotePosition: 50, remotePlaying: true, remoteUpdatedAtLocalMs: 5900, localNowMs: 6000,
            lastAppliedMs: 4000, ownClientId: "me", updatedBy: "host", localPlaying: true
        )
        XCTAssertFalse(tolerated.shouldAct, "drift below 0.6s + lookahead must be tolerated")

        // Play-state change always acts.
        let stateChange = TogetherProtocol.decideApply(
            remotePosition: 50, remotePlaying: false, remoteUpdatedAtLocalMs: 5900, localNowMs: 6000,
            lastAppliedMs: 4000, ownClientId: "me", updatedBy: "host", localPlaying: true
        )
        XCTAssertTrue(stateChange.shouldAct)

        // Large drift acts (age 10s > tolerance).
        let drift = TogetherProtocol.decideApply(
            remotePosition: 100, remotePlaying: true, remoteUpdatedAtLocalMs: 5000, localNowMs: 6000,
            lastAppliedMs: 4000, ownClientId: "me", updatedBy: "host", localPlaying: false
        )
        XCTAssertTrue(drift.shouldAct)
    }

    func testSeekCoalescing() {
        XCTAssertTrue(TogetherProtocol.shouldSendSeek(lastSeekSentAtMs: nil, nowMs: 0))
        XCTAssertFalse(TogetherProtocol.shouldSendSeek(lastSeekSentAtMs: 1000, nowMs: 1100))
        XCTAssertTrue(TogetherProtocol.shouldSendSeek(lastSeekSentAtMs: 1000, nowMs: 1300))
        XCTAssertTrue(TogetherProtocol.isStaleSeek(sequence: 5, lastAppliedSequence: 5))
        XCTAssertFalse(TogetherProtocol.isStaleSeek(sequence: 6, lastAppliedSequence: 5))
    }

    func testSourceMatching() {
        // Exact hash match → same badge.
        let same = TogetherProtocol.matchSource(
            candidate: ("ABC123", "1080p", 5_000_000_000, "Show Title S01E01", "GROUP"),
            host: ("abc123", "1080p", 5_000_000_000, "Show Title S01E01", "GROUP")
        )
        XCTAssertEqual(same.badge, .same)
        XCTAssertEqual(same.score, 1000 + 200 + 150 + 120 + 40)

        // Resolution + title only → close.
        let close = TogetherProtocol.matchSource(
            candidate: ("DEF456", "1080p", 5_000_000_000, "Show Title S01E01", nil),
            host: ("ABC123", "1080p", 5_000_000_000, "Show Title S01E01", nil)
        )
        XCTAssertEqual(close.badge, .close)
        XCTAssertTrue(close.score >= 300 && close.score < 1000)

        // Nothing matches.
        let none = TogetherProtocol.matchSource(
            candidate: ("DEF456", "720p", 1_000_000_000, "Totally Different", nil),
            host: ("ABC123", "1080p", 5_000_000_000, "Show Title S01E01", nil)
        )
        XCTAssertEqual(none.badge, .none)
        XCTAssertTrue(none.score < 300)
    }

    func testInviteParsing() {
        let url = URL(string: "https://app.harbor.site/?harbor-relay=wss://pub.harbor.site&harbor-room=ABC123")!
        let invite = TogetherProtocol.parseInvite(url: url)
        XCTAssertEqual(invite?.relay, "wss://pub.harbor.site")
        XCTAssertEqual(invite?.room, "ABC123")
        XCTAssertNil(TogetherProtocol.parseInvite(url: URL(string: "https://app.harbor.site/")!))
        XCTAssertNil(TogetherProtocol.parseInvite(url: URL(string: "https://app.harbor.site/?harbor-room=B@D!")!))
    }

    func testHarborConstants() {
        XCTAssertEqual(TogetherProtocol.syncDriftToleranceSeconds, 0.6)
        XCTAssertEqual(TogetherProtocol.syncSeekJumpSeconds, 10.0)
        XCTAssertEqual(TogetherProtocol.syncMaxAgeSeconds, 30.0)
        XCTAssertEqual(TogetherProtocol.syncPlayLookaheadSeconds, 0.4)
        XCTAssertEqual(TogetherProtocol.hostHeartbeatMs, 1000)
        XCTAssertEqual(TogetherProtocol.syncSuppressMs, 1400)
        XCTAssertEqual(TogetherProtocol.requiredRelayVersion, 10)
    }
}
