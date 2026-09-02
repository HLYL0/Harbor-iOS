import Foundation

// MARK: - Per-profile settings store (Phase 3).
// Ports Harbor's model: one JSON blob per profile (`harbor.settings.<id>` or `.shared`),
// DEFAULT ∪ parsed ∪ sanitizers, flag-based migrations, atomic writes.
// iOS improvement (documented in IOS_SECURITY.md): secrets never live here — Keychain only.

public protocol SettingsStoring: Sendable {
    func load(profileID: String) async -> AppSettings
    func save(_ settings: AppSettings, profileID: String) async throws
}

public actor SettingsStore: SettingsStoring {

    public static let shared = SettingsStore()

    private let fileManager: FileManager
    private let storeDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.storeDirectory = base.appendingPathComponent("Harbor", isDirectory: true)
        self.encoder.outputFormatting = [.sortedKeys]
        try? fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    private func fileURL(profileID: String) -> URL {
        storeDirectory.appendingPathComponent("settings-\(profileID).json")
    }

    public func load(profileID: String) async -> AppSettings {
        let url = fileURL(profileID: profileID)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return AppSettings()
        }
        let migrated = SettingsMigrator.migrate(raw: raw)
        do {
            let migratedData = try JSONSerialization.data(withJSONObject: migrated)
            var settings = try decoder.decode(AppSettings.self, from: migratedData)
            SettingsMigrator.sanitize(&settings)
            return settings
        } catch {
            // Corrupt blob: quarantine it and fall back to defaults (Harbor's per-section fallback model).
            try? fileManager.moveItem(at: url, to: url.appendingPathExtension("corrupt"))
            return AppSettings()
        }
    }

    public func save(_ settings: AppSettings, profileID: String) async throws {
        var toSave = settings
        SettingsMigrator.sanitize(&toSave)
        let data = try encoder.encode(toSave)
        let url = fileURL(profileID: profileID)
        // Atomic write: tmp + replace (Harbor's settings_store.rs uses the same pattern).
        let tmp = url.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.moveItem(at: tmp, to: url)
    }
}
