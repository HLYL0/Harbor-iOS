import Foundation
import CryptoKit
import CommonCrypto

// MARK: - Profiles + PIN (Phase 16, audit sync-storage.md §8).
// Harbor parity: per-profile settings, session-scoped unlock, kid curfew.
// Security improvement (documented in IOS_KNOWN_LIMITATIONS.md): PIN hashing uses
// PBKDF2-SHA256 (Harbor uses SHA-256 with a static salt — brute-forceable).
// Backup import still accepts Harbor's SHA-256 hash format for compatibility.

struct UserProfile: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var avatar: String?
    var isPrimary: Bool
    /// Which profile's Stremio account this profile uses (Harbor shareStremioWith).
    var shareStremioWith: String?
    var passwordHash: String?
    var hideContent: HideContent
    var lockedTabs: [String]
    var kid: KidSettings?

    struct HideContent: Codable, Equatable, Sendable {
        var adult: Bool
        var titles: Bool

        init(adult: Bool = true, titles: Bool = false) {
            self.adult = adult
            self.titles = titles
        }
    }

    struct KidSettings: Codable, Equatable, Sendable {
        var age: Int?
        var curfewMinutes: Int
        var parentPinHash: String?

        init(age: Int? = nil, curfewMinutes: Int = 0, parentPinHash: String? = nil) {
            self.age = age
            self.curfewMinutes = curfewMinutes
            self.parentPinHash = parentPinHash
        }
    }

    init(
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

    var isLocked: Bool {
        passwordHash != nil && !lockedTabs.isEmpty
    }
}

// MARK: - PIN hashing

enum ProfilePIN {

    /// Harbor's exact scheme (kept ONLY for importing Harbor backups):
    /// SHA-256("harbor-profile-v1|" + pin), hex-encoded.
    static func harborLegacyHash(pin: String) -> String {
        let salted = "harbor-profile-v1|\(pin)"
        let digest = SHA256.hash(data: Data(salted.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func isHarborLegacyHash(_ hash: String) -> Bool {
        hash.count == 64 && hash.allSatisfy { $0.isHexDigit }
    }

    /// Native scheme: PBKDF2-SHA256, 100k iterations, per-hash random salt.
    /// Format: "pbkdf2sha256:<iterations>:<salt-b64>:<hash-b64>".
    static func hash(pin: String) -> String {
        var saltBytes = [UInt8](repeating: 0, count: 16)
        let result = SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes)
        assert(result == errSecSuccess)
        let salt = Data(saltBytes)
        let iterations = 100_000
        let derived = pbkdf2SHA256(password: pin, salt: salt, iterations: iterations)
        return "pbkdf2sha256:\(iterations):\(salt.base64EncodedString()):\(derived.base64EncodedString())"
    }

    /// Verifies either scheme; legacy hashes verify against Harbor's static-salt format.
    static func verify(pin: String, hash: String) -> Bool {
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
        let status: Int32 = derived.withUnsafeMutableBytes { output in
            salt.withUnsafeBytes { saltBytes in
                password.withCString { passwordPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPtr, password.utf8.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        output.baseAddress?.assumingMemoryBound(to: UInt8.self), 32
                    )
                }
            }
        }
        guard status == kCCSuccess else { return Data() }
        return derived
    }
}

// MARK: - Profile store

protocol ProfileStoring: Sendable {
    func profiles() async -> [UserProfile]
    func activeProfileId() async -> String
    func setActive(_ id: String) async
    func save(_ profiles: [UserProfile]) async throws
}

actor ProfileStore: ProfileStoring {

    static let shared = ProfileStore()

    private let cache: AppCache
    private var memory: (profiles: [UserProfile], activeId: String)?
    private var unlockedProfiles: Set<String> = []

    init(cache: AppCache = .shared) {
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

    func profiles() async -> [UserProfile] {
        state().profiles
    }

    func activeProfileId() async -> String {
        state().activeId
    }

    func setActive(_ id: String) async {
        let current = state()
        memory = (current.profiles, id)
        persist(memory!)
        // Session-scoped unlock resets on profile switch (Harbor parity).
        unlockedProfiles.removeAll()
    }

    func save(_ profiles: [UserProfile]) async throws {
        let current = state()
        memory = (profiles, current.activeId)
        persist(memory!)
    }

    private func persist(_ state: (profiles: [UserProfile], activeId: String)) {
        cache.set(PersistedState(profiles: state.profiles, activeId: state.activeId), key: "state", namespace: "profiles", ttl: nil)
    }

    // MARK: - Lock state (Harbor: session-scoped unlock)

    func unlock(_ profileId: String) {
        unlockedProfiles.insert(profileId)
    }

    func isUnlocked(_ profileId: String) -> Bool {
        unlockedProfiles.contains(profileId)
    }

    /// Tab access gate: locked tabs require the profile to be unlocked this session.
    func canAccess(tab: String, profile: UserProfile) -> Bool {
        if !profile.lockedTabs.contains(tab) { return true }
        return isUnlocked(profile.id)
    }
}

// MARK: - Kid curfew (Harbor curfew.ts: daily play-time budget)

struct CurfewState: Codable, Equatable, Sendable {
    var date: String        // "yyyy-MM-dd"
    var seconds: Int
    var unlocked: Bool

    init(date: String, seconds: Int = 0, unlocked: Bool = false) {
        self.date = date
        self.seconds = seconds
        self.unlocked = unlocked
    }
}

actor CurfewTracker {

    static let shared = CurfewTracker()

    private let cache: AppCache

    init(cache: AppCache = .shared) {
        self.cache = cache
    }

    private func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }

    func state(profileId: String) -> CurfewState {
        let key = todayKey()
        if let stored: CurfewState = cache.get(CurfewState.self, key: "curfew-\(key)", namespace: "curfew/\(profileId)") {
            return stored
        }
        return CurfewState(date: key)
    }

    /// Adds played seconds; returns false when the budget is exhausted.
    func add(seconds: Int, budgetMinutes: Int, profileId: String) -> Bool {
        var current = state(profileId: profileId)
        if current.unlocked { return true }
        let budgetSeconds = budgetMinutes * 60
        guard budgetSeconds > 0 else { return true }
        current.seconds += seconds
        cache.set(current, key: "curfew-\(todayKey())", namespace: "curfew/\(profileId)", ttl: nil)
        return current.seconds <= budgetSeconds
    }

    func unlockToday(profileId: String) {
        var current = state(profileId: profileId)
        current.unlocked = true
        cache.set(current, key: "curfew-\(todayKey())", namespace: "curfew/\(profileId)", ttl: nil)
    }
}
