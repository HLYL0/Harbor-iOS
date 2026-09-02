import Foundation

// MARK: - Playback policy constants — EXACT Harbor values (docs/audit/player.md §1.3–1.6).
// One place for every magic number the player orchestration uses.

enum PlaybackPolicy {

    // Resume & watched
    static let resumeSaveInterval: TimeInterval = 4
    static let minimumResumePosition: TimeInterval = 5
    static let stubMaxSeconds: TimeInterval = 150
    static let watchedRatio: Double = 0.85
    static let resumeDedupeDelta: TimeInterval = 1.5

    // Auto-next
    static let autoNextMinDuration: TimeInterval = 150
    static let startedNearEndRatio: Double = 0.8
    static let autoNextErrorWindow: TimeInterval = 2
    static let liveChannelReloadLimit = 5
    static let liveChannelReloadWindow: TimeInterval = 15

    // Retry ladder
    static let maxAutoretryAttempts = 5
    static let liveReconnectDelayNeverPlayed: TimeInterval = 1.5
    static let liveReconnectDelayAfterPlayed: TimeInterval = 4
    static let suppressEndFileWindow: TimeInterval = 1.5

    // Stall / freeze detectors
    static let slowLoadSeconds: TimeInterval = 50
    static let frozenPositionNeverStartedSeconds: TimeInterval = 75
    static let frozenPositionStartedSeconds: TimeInterval = 18
    static let blackScreenGraceSeconds: TimeInterval = 6
    static let blackScreenP2PGraceSeconds: TimeInterval = 20
    static let stuckAutoretrySeconds: TimeInterval = 18
    static let roomStallSeconds: TimeInterval = 9
    static let engineFirstFrameGraceSeconds: TimeInterval = 20
    static let engineHardCeilingSeconds: TimeInterval = 75
    static let wakeReconnectGapSeconds: TimeInterval = 30

    // Chrome auto-hide (parity: player-utils.ts:21-23)
    static let chromeHideWhenPlaying: TimeInterval = 1.8
    static let chromeHideWhenPaused: TimeInterval = 4.5
    static let chromeResumeDelay: TimeInterval = 1.0

    // Stream switching
    static let streamCheckPillShowDelay: TimeInterval = 1.5
    static let streamCheckPillAutoDismiss: TimeInterval = 5.5
    static let switchPositionPreserveThreshold: TimeInterval = 5

    // Sleep timer presets (Harbor, use-sleep-timer.ts)
    static let sleepTimerPresetsMinutes: [Int] = [15, 30, 45, 60, 120, 180, 240, 360]

    // Preflight probe (audit stream-engine §1.4)
    static let probeAttempts = 3
    static let probeRetryDelay: TimeInterval = 1
    static let preflightTimeout: TimeInterval = 2.5
    static let minRealSizeBytes: Int64 = 5 * 1024 * 1024

    // Link validation (resolve.ts)
    static let validateLinkMinSize: Int64 = 80 * 1024 * 1024
    static let validateLinkMinRatio = 0.4
    static let validateLinkExpectedFloor: Int64 = 100 * 1024 * 1024
    static let validateLinkHeadTimeout: TimeInterval = 5

    // Skip segments (audit §6.5)
    static let skipSegmentMinSeconds: Double = 2
    static let skipSegmentMaxSeconds: Double = 360
    static let skipOutroMinStartFraction = 0.5
    static let skipSegmentActiveTailMargin: Double = 0.75
}

// MARK: - Player capability decisions shared across backends.

struct PlayerEngineSelection: Equatable, Sendable {
    var engine: PlayerEngineKind
    var reason: String
}

enum PlayerEngineKind: String, Equatable, Sendable {
    case mpv
    case avplayer
}
