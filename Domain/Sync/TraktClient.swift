import Foundation

// MARK: - Trakt sync (Phase 17, audit sync-storage.md §1 — exact port).
// Device flow + scrobble state machine + watchlist/history/ratings/recommendations/
// calendar. Token exchange supports Harbor's proxy (parity, zero-config) or a
// user-provided client secret (self-hosted path). Secrets live in Keychain.

public struct TraktSession: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var createdAt: Date
    public var expiresIn: TimeInterval
    public var username: String?

    public init(accessToken: String, refreshToken: String, createdAt: Date = Date(), expiresIn: TimeInterval = 7776000, username: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.createdAt = createdAt
        self.expiresIn = expiresIn
        self.username = username
    }

    public var isValid: Bool {
        // Harbor: token valid until createdAt + expiresIn + 14d refresh threshold.
        Date().timeIntervalSince(createdAt) < expiresIn + 14 * 86400
    }
}

public struct TraktDeviceCode: Codable, Sendable {
    public var deviceCode: String
    public var userCode: String
    public var verificationURL: String
    public var expiresIn: TimeInterval
    public var interval: TimeInterval

    public init(deviceCode: String, userCode: String, verificationURL: String, expiresIn: TimeInterval, interval: TimeInterval) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.expiresIn = expiresIn
        self.interval = interval
    }
}

public enum TraktError: Error, LocalizedError {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval)
    case pending
    case denied
    case expired
    case alreadyRecorded
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .unauthorized: return "Trakt rejected the request (unauthorized)."
        case .rateLimited: return "Trakt rate limit reached."
        case .pending: return "Authorization still pending."
        case .denied: return "Authorization was denied."
        case .expired: return "The device code expired."
        case .alreadyRecorded: return "Already recorded."
        case .invalidResponse: return "Trakt returned an invalid response."
        }
    }
}

// MARK: - Constants (Harbor parity)

enum TraktConfig {
    static let apiBase = "https://api.trakt.tv"
    /// Harbor's hard-coded PUBLIC client id (safe to ship; the secret lives server-side).
    static let publicClientID = "71ef7ea86333eab031c8830f8200df1f2f16ef9a3335a67470be4950ac80b925"
    static let tokenProxy = "https://harbor.site/api/trakt/token"
    static let deviceTokenProxy = "https://harbor.site/api/trakt/device-token"
    static let verifyURL = "https://trakt.tv/activate"
    static let refreshThresholdSeconds: TimeInterval = 14 * 86400
    static let writeMinIntervalMs = 1000
    /// Scrobble ignores media shorter than this (Harbor STUB_MAX_SEC).
    static let stubMaxSeconds = 150.0
    /// Playback crossing this % sends stop at progress 100 (Trakt auto-marks watched).
    static let watchedMarkPercent = 70.0
}

// MARK: - Client

actor TraktClient {

    static let shared = TraktClient()

    private let network: NetworkClient
    private let keychain: KeychainStore
    private let sessionAccount = "trakt-session"
    private var session: TraktSession?
    private var lastWriteAt: Date = .distantPast
    private var refreshInFlight = false


    init(network: NetworkClient = .shared, keychain: KeychainStore = KeychainStore()) {
        self.network = network
        self.keychain = keychain
        self.session = keychain.readCodable(TraktSession.self, account: sessionAccount)
    }

    // MARK: - Device flow (Harbor device-auth.ts)

    func requestDeviceCode() async throws -> TraktDeviceCode {
        struct DeviceCodeResponse: Decodable {
            var device_code: String
            var user_code: String
            var verification_url: String
            var expires_in: Double
            var interval: Double
        }
        var request = URLRequest(url: URL(string: "\(TraktConfig.apiBase)/oauth/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["client_id": TraktConfig.publicClientID])
        let (data, response) = try await network.data(for: request, policy: .none)
        guard response.statusCode == 200 else {
            throw response.statusCode == 429 ? TraktError.rateLimited(retryAfter: 30) : TraktError.invalidResponse
        }
        let code = try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
        return TraktDeviceCode(
            deviceCode: code.device_code,
            userCode: code.user_code,
            verificationURL: code.verification_url,
            expiresIn: code.expires_in,
            interval: code.interval
        )
    }

    /// Polls for tokens. Harbor's ladder: 200 = tokens, 400 = pending, 429 = slow_down,
    /// 410 = expired, 418 = denied.
    func pollDeviceCode(_ code: TraktDeviceCode) async throws -> TraktSession {
        struct TokenResponse: Decodable {
            var access_token: String
            var refresh_token: String
            var expires_in: Double?
        }
        var request = URLRequest(url: URL(string: TraktConfig.deviceTokenProxy)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code.deviceCode])
        let (data, response) = try await network.data(for: request, policy: .none)
        switch response.statusCode {
        case 200:
            let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
            var session = TraktSession(
                accessToken: tokens.access_token,
                refreshToken: tokens.refresh_token,
                expiresIn: tokens.expires_in ?? 7776000
            )
            if let username = try? await fetchUsername(accessToken: tokens.access_token) {
                session.username = username
            }
            self.session = session
            keychain.writeCodable(session, account: sessionAccount)
            return session
        case 400: throw TraktError.pending
        case 410: throw TraktError.expired
        case 418: throw TraktError.denied
        case 429: throw TraktError.rateLimited(retryAfter: 30)
        default: throw TraktError.invalidResponse
        }
    }

    func fetchUsername(accessToken: String) async throws -> String {
        struct UserResponse: Decodable { var username: String }
        var request = URLRequest(url: URL(string: "\(TraktConfig.apiBase)/users/me")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("trakt.api-version", forHTTPHeaderField: "2")
        request.setValue(TraktConfig.publicClientID, forHTTPHeaderField: "trakt-api-key")
        let (data, _) = try await network.data(for: request, policy: .none)
        return try JSONDecoder().decode(UserResponse.self, from: data).username
    }

    // MARK: - Authenticated request helper (refresh on 401, 429 retry)

    private func authorizedData(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let session else { throw TraktError.unauthorized }
        var authed = request
        authed.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        authed.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authed.setValue("trakt.api-version", forHTTPHeaderField: "2")
        authed.setValue(TraktConfig.publicClientID, forHTTPHeaderField: "trakt-api-key")

        let (data, response) = try await network.data(for: authed, policy: .none)
        if response.statusCode == 401 {
            try await refreshToken()
            guard let refreshed = self.session else { throw TraktError.unauthorized }
            authed.setValue("Bearer \(refreshed.accessToken)", forHTTPHeaderField: "Authorization")
            return try await network.data(for: authed, policy: .none)
        }
        return (data, response)
    }

    func refreshToken() async throws {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }
        guard let session else { throw TraktError.unauthorized }
        struct RefreshResponse: Decodable {
            var access_token: String
            var refresh_token: String
            var expires_in: Double?
        }
        var request = URLRequest(url: URL(string: TraktConfig.tokenProxy)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "refresh_token": session.refreshToken,
            "grant_type": "refresh_token",
        ])
        let (data, response) = try await network.data(for: request, policy: .none)
        guard response.statusCode == 200 else {
            clearSession()
            throw TraktError.unauthorized
        }
        let tokens = try JSONDecoder().decode(RefreshResponse.self, from: data)
        let refreshed = TraktSession(
            accessToken: tokens.access_token,
            refreshToken: tokens.refresh_token,
            expiresIn: tokens.expires_in ?? session.expiresIn,
            username: session.username
        )
        self.session = refreshed
        keychain.writeCodable(refreshed, account: sessionAccount)
    }

    func clearSession() {
        session = nil
        try? keychain.delete(account: sessionAccount)
    }

    // MARK: - Scrobble state machine (Harbor scrobble-hook.ts)

    /// start → scrobble start; pause only if pauseListStatusOnPause; stop at ≥70% ⇒
    /// progress 100 (watched); 409 on stop = already-recorded (no retry storm);
    /// stop-failure falls back to POST /sync/history.
    func scrobbleStart(media: TraktMediaRef, progress: Double) async throws {
        guard media.durationSeconds ?? 0 >= TraktConfig.stubMaxSeconds else { return }
        let body: [String: Any] = [
            "movie": media.movieID.map { ["ids": ["imdb": $0]] } ?? [:],
            "show": media.showID.map { ["ids": ["imdb": $0]] } ?? [:],
            "episode": media.episode.map { ["season": $0.season, "number": $0.episode] } ?? [:],
            "progress": progress * 100,
        ]
        _ = try await post("/scrobble/start", body: body)
    }

    func scrobblePause(media: TraktMediaRef, progress: Double, pauseListStatusOnPause: Bool) async throws {
        guard pauseListStatusOnPause else { return }
        let body = scrobbleBody(media: media, progress: progress)
        _ = try await post("/scrobble/pause", body: body)
    }

    func scrobbleStop(media: TraktMediaRef, progress: Double, durationSeconds: Double?) async throws {
        let watchedProgress = progress * 100 >= TraktConfig.watchedMarkPercent ? 100.0 : progress * 100
        let body = scrobbleBody(media: media, progress: watchedProgress)
        do {
            _ = try await post("/scrobble/stop", body: body)
        } catch TraktError.rateLimited {
            throw TraktError.rateLimited(retryAfter: 30)
        } catch {
            // Harbor: stop-failure fallback → POST /sync/history (marks watched best-effort).
            var historyBody = body
            historyBody["watched_at"] = ISO8601DateFormatter().string(from: Date())
            _ = try? await post("/sync/history", body: historyBody)
        }
    }

    private func scrobbleBody(media: TraktMediaRef, progress: Double) -> [String: Any] {
        var body: [String: Any] = ["progress": progress]
        if let movieID = media.movieID {
            body["movie"] = ["ids": ["imdb": movieID]]
        } else if let showID = media.showID {
            body["show"] = ["ids": ["imdb": showID]]
            if let episode = media.episode {
                body["episode"] = ["season": episode.season, "number": episode.episode]
            }
        }
        return body
    }

    private func post(_ path: String, body: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: "\(TraktConfig.apiBase)\(path)")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await authorizedData(for: request)
        switch response.statusCode {
        case 200, 201, 202: return (data, response)
        case 409: throw TraktError.alreadyRecorded
        case 429: throw TraktError.rateLimited(retryAfter: 30)
        case 401: throw TraktError.unauthorized
        default: throw TraktError.invalidResponse
        }
    }

    private func get(_ path: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "\(TraktConfig.apiBase)\(path)")!)
        let (data, response) = try await authorizedData(for: request)
        switch response.statusCode {
        case 200: return data
        case 401: throw TraktError.unauthorized
        case 429: throw TraktError.rateLimited(retryAfter: 30)
        default: throw TraktError.invalidResponse
        }
    }

    // MARK: - Read surfaces (Harbor endpoint inventory)

    /// GET /sync/watchlist?sort_by=added&sort_how=desc
    func watchlist() async throws -> [[String: Any]] {
        struct WatchlistResponse: Decodable { var error: String? }
        let data = try await get("/sync/watchlist?sort_by=added&sort_how=desc")
        guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw TraktError.invalidResponse
        }
        return items
    }

    /// GET /sync/history?limit=200
    func history(limit: Int = 200) async throws -> [[String: Any]] {
        let data = try await get("/sync/history?limit=\(limit)")
        guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw TraktError.invalidResponse
        }
        return items
    }

    /// GET /recommendations/{movies,shows}?limit=40&ignore_collected=true
    func recommendations(kind: String, limit: Int = 40) async throws -> [[String: Any]] {
        let data = try await get("/recommendations/\(kind)?limit=\(limit)&ignore_collected=true")
        guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw TraktError.invalidResponse
        }
        return items
    }

    /// GET /calendars/my/shows/{today}/{days}
    func myCalendar(kind: String, days: Int) async throws -> [[String: Any]] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let today = formatter.string(from: Date())
        let data = try await get("/calendars/my/\(kind)/\(today)/\(days)")
        guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw TraktError.invalidResponse
        }
        return items
    }
}

public struct TraktMediaRef: Sendable {
    public var movieID: String?      // tt…
    public var showID: String?       // tt…
    public var episode: (season: Int, episode: Int)?
    public var durationSeconds: Double?

    public init(movieID: String? = nil, showID: String? = nil, episode: (season: Int, episode: Int)? = nil, durationSeconds: Double? = nil) {
        self.movieID = movieID
        self.showID = showID
        self.episode = episode
        self.durationSeconds = durationSeconds
    }
}
