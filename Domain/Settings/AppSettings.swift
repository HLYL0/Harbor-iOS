import Foundation

// MARK: - Application settings model (Phase 3).
// Mirrors the Harbor settings surface we implement so far; flag-based migrations
// follow Harbor's presence-flag model (docs/audit/sync-storage.md §6.3).

struct AppSettings: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var migrationFlags: [String: Bool]

    // Identity / profile
    var activeProfileId: String

    // Language & region
    var uiLanguage: String
    var region: String

    // Home customization (Harbor: settings.homeRows — parity surface, Phase 6 fills it)
    var homeRowsOrder: [String]
    var homeRowsHidden: Set<String>

    // Player preferences (Harbor defaults, per audit)
    var playerEngine: String            // "auto" | "mpv" | "avplayer"
    var autoPlayNextEpisode: Bool
    var pauseListStatusOnPause: Bool
    var resumePrompt: Bool
    var sleepTimerMinutes: Int?

    // Subtitles
    var subProvidersEnabled: Set<String>  // wyzie, opensubtitles, jimaku, addons
    var subtitleAutoSync: Bool            // default false (Harbor)
    var subDelayMs: Int
    var subStylePresetId: String?

    // Adult content
    var showAdultAddons: Bool             // default false (Harbor)

    // Deep links
    var stremioDeeplinkInstall: Bool      // default true (Harbor)

    // Watch together
    var togetherRelayUrl: String
    var togetherShareCursors: Bool

    // Tracker blocking (privacy blocker)
    var trackerBlockingEnabled: Bool      // default true

    init(
        schemaVersion: Int = 1,
        migrationFlags: [String: Bool] = [:],
        activeProfileId: String = "guest",
        uiLanguage: String = "en",
        region: String = "",
        homeRowsOrder: [String] = [],
        homeRowsHidden: Set<String> = [],
        playerEngine: String = "auto",
        autoPlayNextEpisode: Bool = true,
        pauseListStatusOnPause: Bool = false,
        resumePrompt: Bool = true,
        sleepTimerMinutes: Int? = nil,
        subProvidersEnabled: Set<String> = ["wyzie", "opensubtitles", "addons"],
        subtitleAutoSync: Bool = false,
        subDelayMs: Int = 0,
        subStylePresetId: String? = nil,
        showAdultAddons: Bool = false,
        stremioDeeplinkInstall: Bool = true,
        togetherRelayUrl: String = "wss://pub.harbor.site",
        togetherShareCursors: Bool = true,
        trackerBlockingEnabled: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.migrationFlags = migrationFlags
        self.activeProfileId = activeProfileId
        self.uiLanguage = uiLanguage
        self.region = region
        self.homeRowsOrder = homeRowsOrder
        self.homeRowsHidden = homeRowsHidden
        self.playerEngine = playerEngine
        self.autoPlayNextEpisode = autoPlayNextEpisode
        self.pauseListStatusOnPause = pauseListStatusOnPause
        self.resumePrompt = resumePrompt
        self.sleepTimerMinutes = sleepTimerMinutes
        self.subProvidersEnabled = subProvidersEnabled
        self.subtitleAutoSync = subtitleAutoSync
        self.subDelayMs = subDelayMs
        self.subStylePresetId = subStylePresetId
        self.showAdultAddons = showAdultAddons
        self.stremioDeeplinkInstall = stremioDeeplinkInstall
        self.togetherRelayUrl = togetherRelayUrl
        self.togetherShareCursors = togetherShareCursors
        self.trackerBlockingEnabled = trackerBlockingEnabled
    }
}

// MARK: - One-shot presence-flag migrations (Harbor model).

enum SettingsMigrator {

    /// Applied to the raw JSON before decoding. Each migration runs exactly once,
    /// gated by a `_<flag>` key, exactly like Harbor's `_stremioDeeplinkOnByDefault`
    /// style flags (audit sync-storage §6.3).
    static func migrate(raw: [String: Any]) -> [String: Any] {
        var dict = raw
        var flags = dict["migrationFlags"] as? [String: Bool] ?? [:]

        // v1: tracker blocking defaulted ON for existing installs (Harbor parity: forced-on upgrades).
        if flags["_trackerBlockOnByDefault"] != true {
            if dict["trackerBlockingEnabled"] == nil {
                dict["trackerBlockingEnabled"] = true
            }
            flags["_trackerBlockOnByDefault"] = true
        }
        // v1: stremio deep-link install default true for upgrades (Harbor forces it on upgrade).
        if flags["_stremioDeeplinkOnByDefault"] != true {
            if dict["stremioDeeplinkInstall"] == nil {
                dict["stremioDeeplinkInstall"] = true
            }
            flags["_stremioDeeplinkOnByDefault"] = true
        }

        dict["migrationFlags"] = flags
        dict["schemaVersion"] = 1
        return dict
    }

    /// Sanitizers (Harbor load.ts sanitization model): clamp invalid values back to defaults.
    static func sanitize(_ settings: inout AppSettings) {
        if !["auto", "mpv", "avplayer"].contains(settings.playerEngine) {
            settings.playerEngine = "auto"
        }
        if !["en", "ar", "pt", "ru"].contains(settings.uiLanguage) {
            settings.uiLanguage = "en"
        }
        if settings.subDelayMs < -60_000 || settings.subDelayMs > 60_000 {
            settings.subDelayMs = 0
        }
        // Subtitle providers allowlist.
        let allowedProviders: Set<String> = ["wyzie", "opensubtitles", "jimaku", "addons"]
        settings.subProvidersEnabled.formIntersection(allowedProviders)
    }
}
