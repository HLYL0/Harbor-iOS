import Foundation
import CryptoKit

// MARK: - Profiles + PIN (Phase 16, audit sync-storage.md §8).
// Harbor parity: per-profile settings, session-scoped unlock, kid curfew.
// Security improvement (documented in IOS_KNOWN_LIMITATIONS.md): PIN hashing uses
// PBKDF2-SHA256 (Harbor uses SHA-256 with a static salt — brute-forceable).
// Backup import still accepts Harbor's SHA-256 hash format for compatibility.

public struct UserProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var avatar: String?
    public var isPrimary: Bool
    /// Which profile's Stremio account this profile uses (Harbor shareStremioWith).
    public var shareStremioWith: String?
    public var passwordHash: String?
    public var hideContent: HideContent
    public var lockedTabs: [String]
    public var kid: KidSettings?

    public struct HideContent: Codable, Equatable, Sendable {
        public var adult: Bool
        public var titles: Bool

        public init(adult: Bool = true, titles: Bool = false) {
            self.adult = adult
            self.titles = titles
        }
    }

    public struct KidSettings: Codable, Equatable, Sendable {
        public var age: Int?
        public var curfewMinutes: Int
        public var parentPinHash: String?

        public init(age: Int? = nil, curfewMinutes: Int = 0, parentPinHash: String? = nil) {
            self.age = age
            self.curfewMinutes = curfewMinutes
            self.parentPinHash = parentPinHash
        }
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        avatar: String? = nil,
        isPrimary: Bool = false,
        shareStremioWith: String? = nil,
        passwordHash: String? = nil,
        hideContent: HideContent = HideContent(),
        lockedTabs: [String] = [],
        kid: KidSettings? = nil
    ) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.isPrimary = isPrimary
        self.shareStremioWith = shareStremioWith
        self.passwordHash = passwordHash
        self.hideContent = hideContent
        self.lockedTabs = lockedTabs
        self.kid = kid
    }

    public var isLocked: Bool {
        passwordHash != nil && !lockedTabs.isEmpty
    }
}

// MARK: - PIN hashing

public enum ProfilePIN {

    /// Harbor's exact scheme (kept ONLY for importing Harbor backups):
    /// SHA-256("harbor-profile-v1|" + pin), hex-encoded.
    public static func harborLegacyHash(pin: String) -> String {
        let salted = "harbor-profile-v1|\(pin)"
        let digest = SHA256.hash(data: Data(salted.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func isHarborLegacyHash(_ hash: String) -> Bool {
        hash.count == 64 && hash.allSatisfy { $0.isHexDigit }
    }

    /// Native scheme: PBKDF2-SHA256, 100k iterations, per-hash random salt.
    /// Format: "pbkdf2sha256:<iterations>:<salt-b64>:<hash-b64>".
    public static func hash(pin: String) -> String {
        var saltBytes = [UInt8](repeating: 0, count: 16)
        let result = SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes)
        assert(result == errSecSuccess)
        let salt = Data(saltBytes)
        let iterations = 100_000
        let derived = pbkdf2SHA256(password: pin, salt: salt, iterations: iterations)
        return "pbkdf2sha256:\(iterations):\(salt.base64EncodedString()):\(derived.base64EncodedString())"
    }

    /// Verifies either scheme; legacy hashes verify against Harbor's static-salt format.
    public static func verify(pin: String, hash: String) -> Bool {
        let parts = hash.split(separator: ":").map(String.init)
        if parts.count == 4, parts[0] == "pbkdf2sha256",
           let iterations = Int(parts[1]),
           let salt = Data(base64Encoded: parts[2]),
           let expected = Data(base64Encoded: parts[3]) {
            let derived = pbkdf2SHA256(password: pin, salt: salt, iterations: iterations)
            return derived == expected
        }
        if isHarborLegacyHash(hash) {
            return harborLegacyHash(pin: pin) == hash.lowercased()
        }
        return false
    }

    static func pbkdf2SHA256(password: String, salt: Data, iterations: Int) -> Data {
        var derived = Data(repeating: 0, count: 32)
        derived.withUnsafeMutableBytes { buffer in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                password, password.utf8.count,
                (salt as NSData).bytes.bindMemory(to: UInt8.self, capacity: salt.count), salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                buffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                32
            )
        }
        return derived
    }
}

// MARK: - Profile store

public protocol ProfileStoring: Sendable {
    func profiles() async -> [UserProfile]
    func activeProfileId() async -> String
    func setActive(_ id: String) async
    func save(_ profiles: [UserProfile]) async throws
}

public actor ProfileStore: ProfileStoring {

    public static let shared = ProfileStore()

    private let cache: AppCache
    private var memory: (profiles: [UserProfile], activeId: String)?
    private var unlockedProfiles: Set<String> = []

    public init(cache: AppCache = .shared) {
        self.cache = cache
    }

    private struct PersistedState: Codable {
        var profiles: [UserProfile]
        var activeId: String
    }

    private func state() -> (profiles: [UserProfile], activeId: String) {
        if let memory { return memory }
        let persisted: PersistedState = cache.get(PersistedState.self, key: "state", namespace: "profiles")
            ?? PersistedState(profiles: [], activeId: "guest")
        memory = (persisted.profiles, persisted.activeId)
        return memory!
    }

    public func profiles() async -> [UserProfile] {
        state().profiles
    }

    public func activeProfileId() async -> String {
        state().activeId
    }

    public func setActive(_ id: String) async {
        let current = state()
        memory = (current.profiles, id)
        persist(memory!)
        // Session-scoped unlock resets on profile switch (Harbor parity).
        unlockedProfiles.removeAll()
    }

    public func save(_ profiles: [UserProfile]) async throws {
        let current = state()
        memory = (profiles, current.activeId)
        persist(memory!)
    }

    private func persist(_ state: (profiles: [UserProfile], activeId: String)) {
        cache.set(PersistedState(profiles: state.profiles, activeId: state.activeId), key: "state", namespace: "profiles", ttl: nil)
    }

    // MARK: - Lock state (Harbor: session-scoped unlock)

    public func unlock(_ profileId: String) {
        unlockedProfiles.insert(profileId)
    }

    public func isUnlocked(_ profileId: String) -> Bool {
        unlockedProfiles.contains(profileId)
    }

    /// Tab access gate: locked tabs require the profile to be unlocked this session.
    public func canAccess(tab: String, profile: UserProfile) -> Bool {
        if !profile.lockedTabs.contains(tab) { return true }
        return isUnlocked(profile.id)
    }
}

// MARK: - Kid curfew (Harbor curfew.ts: daily play-time budget)

public struct CurfewState: Codable, Equatable, Sendable {
    public var date: String        // "yyyy-MM-dd"
    public var seconds: Int
    public var unlocked: Bool

    public init(date: String, seconds: Int = 0, unlocked: Bool = false) {
        self.date = date
        self.seconds = seconds
        self.unlocked = unlocked
    }
}

public actor CurfewTracker {

    public static let shared = CurfewTracker()

    private let cache: AppCache

    public init(cache: AppCache = .shared) {
        self.cache = cache
    }

    private func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }

    public func state(profileId: String) -> CurfewState {
        let key = todayKey()
        if let stored: CurfewState = cache.get(CurfewState.self, key: "curfew-\(key)", namespace: "curfew/\(profileId)") {
            return stored
        }
        return CurfewState(date: key)
    }

    /// Adds played seconds; returns false when the budget is exhausted.
    public func add(seconds: Int, budgetMinutes: Int, profileId: String) -> Bool {
        var current = state(profileId: profileId)
        if current.unlocked { return true }
        let budgetSeconds = budgetMinutes * 60
        guard budgetSeconds > 0 else { return true }
        current.seconds += seconds
        cache.set(current, key: "curfew-\(todayKey())", namespace: "curfew/\(profileId)", ttl: nil)
        return current.seconds <= budgetSeconds
    }

    public func unlockToday(profileId: String) {
        var current = state(profileId: profileId)
        current.unlocked = true
        cache.set(current, key: "curfew-\(todayKey())", namespace: "curfew/\(profileId)", ttl: nil)
    }
}
