import Foundation

actor RealDebridClient: DebridServicing {
    private static let base = URL(string: "https://api.real-debrid.com/rest/1.0")!

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func resolve(
        infoHash: String,
        fileIdx: Int?,
        streamName: String?,
        apiKey: String
    ) async throws -> URL {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DebridResolveError.missingAPIKey }
        guard let magnet = DebridResolver.magnetURI(infoHash: infoHash, name: streamName) else {
            throw DebridResolveError.invalidInfoHash
        }

        let add: RealDebridAddMagnetResponse = try await form(
            path: "torrents/addMagnet",
            fields: ["magnet": magnet],
            apiKey: key
        )
        let torrentID = add.id

        let firstInfo = try await pollUntilPlayableFile(id: torrentID, apiKey: apiKey)
        guard let fileIndex = DebridResolver.fileIndex(
            in: firstInfo.files ?? [],
            preferred: fileIdx
        ) else {
            throw DebridResolveError.noPlayableFile
        }

        try await formVoid(
            path: "torrents/selectFiles/\(torrentID)",
            fields: ["files": String(fileIndex)],
            apiKey: key
        )

        let ready = try await pollUntilPlayableFile(id: torrentID, apiKey: key)
        let link = ready.files?.first(where: { $0.selected == 1 })?.link
            ?? ready.links?.first
        guard let link, !link.isEmpty else {
            throw DebridResolveError.noPlayableFile
        }

        let unrestrict: RealDebridUnrestrictResponse = try await form(
            path: "unrestrict/link",
            fields: ["link": link],
            apiKey: key
        )
        guard let url = URL(string: unrestrict.download), url.host?.isEmpty == false else {
            throw DebridResolveError.noPlayableFile
        }
        return url
    }

    private func pollUntilPlayableFile(id: String, apiKey: String) async throws -> RealDebridTorrentInfo {
        for _ in 0..<45 {
            let info: RealDebridTorrentInfo = try await get(
                path: "torrents/info/\(id)",
                apiKey: apiKey
            )
            if let status = info.status, ["error", "dead", "magnet_error", "virus"].contains(status) {
                throw DebridResolveError.api("torrent status: \(status)")
            }
            if let link = info.files?.first(where: { $0.selected == 1 })?.link ?? info.links?.first,
               !link.isEmpty {
                return info
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw DebridResolveError.torrentNotReady
    }

    private func get<Value: Decodable & Sendable>(path: String, apiKey: String) async throws -> Value {
        var request = URLRequest(url: Self.base.appending(path: path))
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("HarborIOS/0.2", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Self.validate(data: data, response: response)
        return try JSONDecoder().decode(Value.self, from: data)
    }

    private func form<Value: Decodable & Sendable>(
        path: String,
        fields: [String: String],
        apiKey: String
    ) async throws -> Value {
        let (data, response) = try await formRequest(path: path, fields: fields, apiKey: apiKey)
        try Self.validate(data: data, response: response)
        return try JSONDecoder().decode(Value.self, from: data)
    }

    private func formVoid(path: String, fields: [String: String], apiKey: String) async throws {
        let (data, response) = try await formRequest(path: path, fields: fields, apiKey: apiKey)
        try Self.validate(data: data, response: response)
    }

    private func formRequest(
        path: String,
        fields: [String: String],
        apiKey: String
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: Self.base.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("HarborIOS/0.2", forHTTPHeaderField: "User-Agent")
        request.httpBody = fields
            .map { key, value in "\(key)=\(Self.formEncoded(value))" }
            .joined(separator: "&")
            .data(using: .utf8)
        return try await session.data(for: request)
    }

    private static func formEncoded(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func validate(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw DebridResolveError.api("invalid response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let detail = message.isEmpty ? "" : ": \(message.prefix(160))"
            throw DebridResolveError.api("HTTP \(http.statusCode)\(detail)")
        }
    }
}
