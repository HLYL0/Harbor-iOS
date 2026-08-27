import Foundation

actor StremioAPIClient: StremioServicing {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func topCatalog(type: String, skip: Int = 0) async throws -> [StremioMeta] {
        let response: CatalogResponse = try await get(StremioEndpoint.cinemetaCatalog(type: type, skip: skip))
        return response.metas
    }

    func searchCatalog(type: String, query: String) async throws -> [StremioMeta] {
        let response: CatalogResponse = try await get(
            StremioEndpoint.cinemetaCatalog(type: type, search: query)
        )
        return response.metas
    }

    func metadata(type: String, id: String) async throws -> StremioMeta {
        let response: MetaResponse = try await get(StremioEndpoint.cinemetaMeta(type: type, id: id))
        return response.meta
    }

    func manifest(at url: URL) async throws -> AddonManifest {
        let manifest: AddonManifest = try await get(url)
        guard !manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StremioClientError.invalidManifest
        }
        return manifest
    }

    func streams(addons: [StremioAddon], type: String, id: String) async -> [AttributedStream] {
        let eligible = addons.filter { $0.manifest.accepts(resource: "stream", type: type, id: id) }
        let collected = await withTaskGroup(of: [AttributedStream].self) { group in
            for addon in eligible {
                group.addTask { [self] in
                    await streams(from: addon, type: type, id: id)
                }
            }

            var output: [AttributedStream] = []
            for await batch in group {
                output.append(contentsOf: batch)
            }
            return output
        }

        var seen = Set<String>()
        let deduplicated = collected.filter { seen.insert($0.stream.id).inserted }
        return deduplicated.sorted { lhs, rhs in
            if lhs.stream.isDirectlyPlayable != rhs.stream.isDirectlyPlayable {
                return lhs.stream.isDirectlyPlayable
            }
            return streamScore(lhs.stream) > streamScore(rhs.stream)
        }
    }

    func login(email: String, password: String) async throws -> StremioLoginResult {
        struct LoginBody: Encodable {
            let email: String
            let password: String
            let facebook = false
        }
        let envelope: APIEnvelope<StremioLoginResult> = try await post(
            StremioEndpoint.accountAPI.appending(path: "login"),
            body: LoginBody(email: email, password: password)
        )
        return try unwrap(envelope)
    }

    func currentUser(authKey: String) async throws -> StremioUser {
        struct AuthBody: Encodable {
            let authKey: String
        }
        let envelope: APIEnvelope<StremioUser> = try await post(
            StremioEndpoint.accountAPI.appending(path: "getUser"),
            body: AuthBody(authKey: authKey)
        )
        return try unwrap(envelope)
    }

    func logout(authKey: String) async throws {
        struct AuthBody: Encodable {
            let authKey: String
        }
        struct StatusEnvelope: Decodable, Sendable {
            let error: APIErrorPayload?
        }
        let envelope: StatusEnvelope = try await post(
            StremioEndpoint.accountAPI.appending(path: "logout"),
            body: AuthBody(authKey: authKey)
        )
        if let message = envelope.error?.message {
            throw StremioClientError.api(message)
        }
    }

    func userAddons(authKey: String) async throws -> [StremioAddon] {
        struct AddonBody: Encodable {
            let authKey: String
            let type = "user"
            let update = false
        }
        let envelope: APIEnvelope<AddonCollectionResult> = try await post(
            StremioEndpoint.accountAPI.appending(path: "addonCollectionGet"),
            body: AddonBody(authKey: authKey)
        )
        return try unwrap(envelope).addons
    }

    private func streams(from addon: StremioAddon, type: String, id: String) async -> [AttributedStream] {
        guard let manifestURL = URL(string: addon.transportUrl),
              let endpoint = StremioEndpoint.streamURL(manifestURL: manifestURL, type: type, id: id) else {
            return []
        }
        do {
            let response: StreamResponse = try await get(endpoint)
            return response.streams.map {
                AttributedStream(
                    stream: $0,
                    addonID: addon.manifest.id,
                    addonName: addon.manifest.name,
                    addonURL: addon.transportUrl
                )
            }
        } catch {
            return []
        }
    }

    private func get<Value: Decodable & Sendable>(_ url: URL) async throws -> Value {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("HarborIOS/0.1", forHTTPHeaderField: "User-Agent")
        return try await perform(request)
    }

    private func post<Body: Encodable, Value: Decodable & Sendable>(
        _ url: URL,
        body: Body
    ) async throws -> Value {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    private func perform<Value: Decodable & Sendable>(_ request: URLRequest) async throws -> Value {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw StremioClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw StremioClientError.httpStatus(http.statusCode)
        }
        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            throw StremioClientError.decodingFailed
        }
    }

    private func unwrap<Value: Decodable & Sendable>(_ envelope: APIEnvelope<Value>) throws -> Value {
        if let result = envelope.result { return result }
        throw StremioClientError.api(envelope.error?.message ?? "Stremio rejected the request.")
    }

    private func streamScore(_ stream: StremioStream) -> Int {
        let value = "\(stream.title ?? "") \(stream.name ?? "")".lowercased()
        if value.contains("2160") || value.contains("4k") { return 400 }
        if value.contains("1080") { return 300 }
        if value.contains("720") { return 200 }
        if value.contains("480") { return 100 }
        return 0
    }
}

enum StremioClientError: Error, LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case decodingFailed
    case invalidManifest
    case api(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The server returned an invalid response."
        case .httpStatus(let status): "The server returned HTTP \(status)."
        case .decodingFailed: "The server response did not match the Stremio protocol."
        case .invalidManifest: "That URL did not return a valid addon manifest."
        case .api(let message): message
        }
    }
}
