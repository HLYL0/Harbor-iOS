import Foundation

// MARK: - Playback policy constants — EXACT Harbor values (docs/audit/player.md §1.3–1.6).
// One place for every magic number the player orchestration uses.

public enum PlaybackPolicy {

    // Resume & watched
    public static let resumeSaveInterval: TimeInterval = 4
    public static let minimumResumePosition: TimeInterval = 5
    public static let stubMaxSeconds: TimeInterval = 150
    public static let watchedRatio: Double = 0.85
    public static let resumeDedupeDelta: TimeInterval = 1.5

    // Auto-next
    public static let autoNextMinDuration: TimeInterval = 150
    public static let startedNearEndRatio: Double = 0.8
    public static let autoNextErrorWindow: TimeInterval = 2
    public static let liveChannelReloadLimit = 5
    public static let liveChannelReloadWindow: TimeInterval = 15

    // Retry ladder
    public static let maxAutoretryAttempts = 5
    public static let liveReconnectDelayNeverPlayed: TimeInterval = 1.5
    public static let liveReconnectDelayAfterPlayed: TimeInterval = 4
    public static let suppressEndFileWindow: TimeInterval = 1.5

    // Stall / freeze detectors
    public static let slowLoadSeconds: TimeInterval = 50
    public static let frozenPositionNeverStartedSeconds: TimeInterval = 75
    public static let frozenPositionStartedSeconds: TimeInterval = 18
    public static let blackScreenGraceSeconds: TimeInterval = 6
    public static let blackScreenP2PGraceSeconds: TimeInterval = 20
    public static let stuckAutoretrySeconds: TimeInterval = 18
    public static let roomStallSeconds: TimeInterval = 9
    public static let engineFirstFrameGraceSeconds: TimeInterval = 20
    public static let engineHardCeilingSeconds: TimeInterval = 75
    public static let wakeReconnectGapSeconds: TimeInterval = 30

    // Chrome auto-hide (parity: player-utils.ts:21-23)
    public static let chromeHideWhenPlaying: TimeInterval = 1.8
    public static let chromeHideWhenPaused: TimeInterval = 4.5
    public static let chromeResumeDelay: TimeInterval = 1.0

    // Stream switching
    public static let streamCheckPillShowDelay: TimeInterval = 1.5
    public static let streamCheckPillAutoDismiss: TimeInterval = 5.5
    public static let switchPositionPreserveThreshold: TimeInterval = 5

    // Sleep timer presets (Harbor, use-sleep-timer.ts)
    public static let sleepTimerPresetsMinutes: [Int] = [15, 30, 45, 60, 120, 180, 240, 360]

    // Preflight probe (audit stream-engine §1.4)
    public static let probeAttempts = 3
    public static let probeRetryDelay: TimeInterval = 1
    public static let preflightTimeout: TimeInterval = 2.5
    public static let minRealSizeBytes: Int64 = 5 * 1024 * 1024

    // Link validation (resolve.ts)
    public static let validateLinkMinSize: Int64 = 80 * 1024 * 1024
    public static let validateLinkMinRatio = 0.4
    public static let validateLinkExpectedFloor: Int64 = 100 * 1024 * 1024
    public static let validateLinkHeadTimeout: TimeInterval = 5

    // Skip segments (audit §6.5)
    public static let skipSegmentMinSeconds: Double = 2
    public static let skipSegmentMaxSeconds: Double = 360
    public static let skipOutroMinStartFraction = 0.5
    public static let skipSegmentActiveTailMargin: Double = 0.75
}

// MARK: - Player capability decisions shared across backends.

public struct PlayerEngineSelection: Equatable, Sendable {
    public var engine: PlayerEngineKind
    public var reason: String
}

public enum PlayerEngineKind: String, Equatable, Sendable {
    case mpv
    case avplayer
}
