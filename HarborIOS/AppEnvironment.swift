import Combine
import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    @Published private(set) var addons: [StremioAddon] = []
    @Published private(set) var user: StremioUser?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isWorking = false
    @Published private(set) var hasDebridKey = false
    @Published var notice: String?
    @Published var actionError: String?

    private static let guestProfileID = "guest"

    private let service: any StremioServicing
    private let debrid: any DebridServicing
    private let persistence: AddonPersistence
    private let keychain: KeychainStore
    let resumeStore: ResumeStore
    let catalogService: CatalogService
    let discoveryClient: any AddonDiscoveryServicing
    let settingsStore: SettingsStore
    private let authAccount = "stremio-auth-key"
    private let debridAccount = "debrid-api-key"

    private var authKey: String?
    private var debridAPIKey: String?
    private var activeProfileID = AppEnvironment.guestProfileID
    private var persistenceState = AddonPersistenceState()
    private var cloudAddons: [StremioAddon] = []

    init(
        service: any StremioServicing = StremioAPIClient(),
        debrid: any DebridServicing = RealDebridClient(),
        persistence: AddonPersistence = AddonPersistence(),
        keychain: KeychainStore = KeychainStore(),
        resumeStore: ResumeStore = .shared,
        catalogService: CatalogService = .shared,
        discoveryClient: any AddonDiscoveryServicing = AddonDiscoveryClient.shared,
        settingsStore: SettingsStore = .shared
    ) {
        self.service = service
        self.debrid = debrid
        self.persistence = persistence
        self.keychain = keychain
        self.resumeStore = resumeStore
        self.catalogService = catalogService
        self.discoveryClient = discoveryClient
        self.settingsStore = settingsStore
    }

    func start() async {
        debridAPIKey = keychain.readString(account: debridAccount)
        hasDebridKey = !(debridAPIKey ?? "").isEmpty
        guard let savedAuthKey = keychain.readString(account: authAccount) else {
            await activateProfile(Self.guestProfileID)
            return
        }

        do {
            let currentUser = try await service.currentUser(authKey: savedAuthKey)
            guard let profileID = profileID(for: currentUser) else {
                throw StremioClientError.invalidResponse
            }
            authKey = savedAuthKey
            user = currentUser
            isAuthenticated = true
            await activateProfile(profileID)
            await syncAddons()
        } catch {
            try? keychain.delete(account: authAccount)
            authKey = nil
            user = nil
            isAuthenticated = false
            await activateProfile(Self.guestProfileID)
            actionError = "Your saved Stremio session expired. Sign in again."
        }
    }

    func topCatalog(type: String) async throws -> [StremioMeta] {
        try await service.topCatalog(type: type, skip: 0)
    }

    func searchCatalog(type: String, query: String) async throws -> [StremioMeta] {
        try await service.searchCatalog(type: type, query: query)
    }

    func metadata(type: String, id: String) async throws -> StremioMeta {
        try await service.metadata(type: type, id: id)
    }

    func streamCandidates(type: String, id: String) async -> [AttributedStream] {
        await service.streams(addons: addons, type: type, id: id)
    }

    /// Continue Watching (Phase 6): unfinished progress from the resume store,
    /// mapped back to lightweight metas for the Home rail.
    func continueWatching() async -> [StremioMeta] {
        let progress = await resumeStore.allProgress()
        return progress.map { entry in
            StremioMeta(
                id: entry.metaId,
                type: entry.metaType,
                name: entry.title ?? "Untitled",
                poster: entry.poster
            )
        }
    }

    func saveProgress(_ progress: PlaybackProgress) async {
        await resumeStore.save(progress)
    }

    func progress(metaId: String) async -> PlaybackProgress? {
        await resumeStore.progress(metaId: metaId)
    }

    func debridResolve(stream: StremioStream) async throws -> URL {
        guard let key = debridAPIKey, !key.isEmpty else {
            throw DebridResolveError.missingAPIKey
        }
        guard let infoHash = stream.infoHash, !infoHash.isEmpty else {
            throw PlaybackSourceError.torrentSourceUnsupported
        }
        return try await debrid.resolve(
            infoHash: infoHash,
            fileIdx: stream.fileIdx,
            streamName: stream.behaviorHints?.fileName ?? stream.behaviorHints?.filename,
            apiKey: key
        )
    }

    func saveDebridAPIKey(_ rawKey: String) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            actionError = "Paste your Real-Debrid API key first."
            return
        }
        do {
            try keychain.writeString(key, account: debridAccount)
            debridAPIKey = key
            hasDebridKey = true
            notice = "Real-Debrid key saved. Torrent sources can now be resolved."
        } catch {
            actionError = "Could not save the key to Keychain."
        }
    }

    func clearDebridAPIKey() async {
        do {
            try keychain.delete(account: debridAccount)
        } catch {
            actionError = "Could not remove the key from Keychain."
            return
        }
        debridAPIKey = nil
        hasDebridKey = false
        notice = "Real-Debrid key removed."
    }

    func login(email: String, password: String) async {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty, !password.isEmpty else {
            actionError = "Enter your Stremio email and password."
            return
        }

        isWorking = true
        actionError = nil
        notice = nil
        defer { isWorking = false }

        do {
            let result = try await service.login(email: cleanEmail, password: password)
            let signedInUser: StremioUser
            if let returnedUser = result.user, profileID(for: returnedUser) != nil {
                signedInUser = returnedUser
            } else {
                signedInUser = try await service.currentUser(authKey: result.authKey)
            }
            guard let profileID = profileID(for: signedInUser) else {
                throw StremioClientError.invalidResponse
            }

            try keychain.writeString(result.authKey, account: authAccount)
            authKey = result.authKey
            user = signedInUser
            isAuthenticated = true
            await activateProfile(profileID)

            do {
                try await refreshCloudAddons(authKey: result.authKey)
                notice = "Signed in and synced your Stremio addons."
            } catch {
                actionError = "Signed in, but addon sync failed: \(error.localizedDescription)"
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    func logout() async {
        let savedAuthKey = authKey
        isWorking = true
        actionError = nil
        notice = nil
        defer { isWorking = false }

        var revocationError: Error?
        if let savedAuthKey {
            do {
                try await service.logout(authKey: savedAuthKey)
            } catch {
                revocationError = error
            }
        }

        var deletionError: Error?
        do {
            try keychain.delete(account: authAccount)
        } catch {
            deletionError = error
        }

        authKey = nil
        user = nil
        isAuthenticated = false
        await activateProfile(Self.guestProfileID)
        notice = "Signed out."

        if deletionError != nil {
            actionError = "Stremio signed out, but the saved session could not be removed from Keychain."
        } else if let revocationError {
            actionError = "Signed out locally, but Stremio could not revoke the server session: \(revocationError.localizedDescription)"
        }
    }

    func syncAddons() async {
        guard let authKey else { return }
        isWorking = true
        actionError = nil
        defer { isWorking = false }

        do {
            try await refreshCloudAddons(authKey: authKey)
            notice = "Synced \(cloudAddons.count) addons from Stremio."
        } catch {
            actionError = error.localizedDescription
        }
    }

    func installAddon(rawURL: String) async {
        guard let manifestURL = StremioEndpoint.normalizeManifestURL(rawURL) else {
            actionError = "Enter a valid HTTPS addon manifest URL."
            return
        }
        isWorking = true
        actionError = nil
        notice = nil
        defer { isWorking = false }

        do {
            let manifest = try await service.manifest(at: manifestURL)
            let addon = StremioAddon(
                manifest: manifest,
                transportUrl: manifestURL.absoluteString,
                transportName: nil,
                flags: AddonFlags(official: false, protected: false)
            )
            persistenceState.installLocal(addon)
            try await persistence.save(persistenceState, profileID: activeProfileID)
            refreshVisibleAddons()
            notice = "Installed \(manifest.name)."
        } catch {
            actionError = error.localizedDescription
        }
    }

    func removeAddon(_ addon: StremioAddon) async {
        persistenceState.remove(addon, cloudAddons: cloudAddons)
        do {
            try await persistence.save(persistenceState, profileID: activeProfileID)
            refreshVisibleAddons()
        } catch {
            actionError = "Could not save the addon list."
        }
    }

    private func activateProfile(_ profileID: String) async {
        activeProfileID = profileID
        persistenceState = await persistence.load(profileID: profileID)
        cloudAddons = []
        refreshVisibleAddons()
    }

    private func refreshCloudAddons(authKey: String) async throws {
        cloudAddons = try await service.userAddons(authKey: authKey)
        refreshVisibleAddons()
    }

    private func refreshVisibleAddons() {
        addons = persistenceState.visibleAddons(cloudAddons: cloudAddons)
    }

    private func profileID(for user: StremioUser) -> String? {
        if let id = user.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            return "stremio-id:\(id)"
        }
        if let email = user.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !email.isEmpty {
            return "stremio-email:\(email)"
        }
        return nil
    }
}
