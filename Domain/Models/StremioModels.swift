import Foundation

struct StremioMeta: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let type: String
    let name: String
    let poster: String?
    let background: String?
    let logo: String?
    let description: String?
    let releaseInfo: String?
    let imdbRating: String?
    let runtime: String?
    let genres: [String]?
    let behaviorHints: MetaBehaviorHints?
    let videos: [StremioVideo]?

    init(
        id: String,
        type: String,
        name: String,
        poster: String? = nil,
        background: String? = nil,
        logo: String? = nil,
        description: String? = nil,
        releaseInfo: String? = nil,
        imdbRating: String? = nil,
        runtime: String? = nil,
        genres: [String]? = nil,
        behaviorHints: MetaBehaviorHints? = nil,
        videos: [StremioVideo]? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.poster = poster
        self.background = background
        self.logo = logo
        self.description = description
        self.releaseInfo = releaseInfo
        self.imdbRating = imdbRating
        self.runtime = runtime
        self.genres = genres
        self.behaviorHints = behaviorHints
        self.videos = videos
    }
}

struct MetaBehaviorHints: Codable, Hashable, Sendable {
    let defaultVideoId: String?
}

struct StremioVideo: Codable, Hashable, Sendable {
    let id: String?
    let season: Int?
    let episode: Int?
    let number: Int?
    let released: String?
    let name: String?
    let title: String?
    let overview: String?
    let description: String?
    let thumbnail: String?

    var stableID: String {
        id ?? "s\(season ?? 0)e\(episode ?? number ?? 0)-\(name ?? title ?? "episode")"
    }

    var displayTitle: String {
        name ?? title ?? "Episode \(episode ?? number ?? 0)"
    }

}

struct StreamSubtitle: Codable, Equatable, Sendable {
    let id: String?
    let url: String
    let lang: String?
    let m: String?

    init(id: String? = nil, url: String, lang: String? = nil, m: String? = nil) {
        self.id = id
        self.url = url
        self.lang = lang
        self.m = m
    }
}

struct ProxyHeaders: Codable, Equatable, Sendable {
    let request: [String: String]?
    let response: [String: String]?
}

struct StreamBehaviorHints: Codable, Equatable, Sendable {
    let bingeGroup: String?
    let videoHash: String?
    let videoSize: Int64?
    let filename: String?
    let fileName: String?
    let notWebReady: Bool?
    let proxyHeaders: ProxyHeaders?
    let headers: [String: String]?

    var requiresCustomHeaders: Bool {
        proxyHeaders?.request?.isEmpty == false || headers?.isEmpty == false
    }
}

struct StremioStream: Codable, Identifiable, Equatable, Sendable {
    let name: String?
    let title: String?
    let description: String?
    let url: String?
    let infoHash: String?
    let fileIdx: Int?
    let ytId: String?
    let externalUrl: String?
    let nzbUrl: String?
    let subtitles: [StreamSubtitle]?
    let behaviorHints: StreamBehaviorHints?
    let sources: [String]?

    init(
        name: String? = nil,
        title: String? = nil,
        description: String? = nil,
        url: String? = nil,
        infoHash: String? = nil,
        fileIdx: Int? = nil,
        ytId: String? = nil,
        externalUrl: String? = nil,
        nzbUrl: String? = nil,
        subtitles: [StreamSubtitle]? = nil,
        behaviorHints: StreamBehaviorHints? = nil,
        sources: [String]? = nil
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.url = url
        self.infoHash = infoHash
        self.fileIdx = fileIdx
        self.ytId = ytId
        self.externalUrl = externalUrl
        self.nzbUrl = nzbUrl
        self.subtitles = subtitles
        self.behaviorHints = behaviorHints
        self.sources = sources
    }

    var id: String {
        if let url, !url.isEmpty { return "url:\(url)" }
        if let infoHash, !infoHash.isEmpty { return "hash:\(infoHash.lowercased()):\(fileIdx ?? -1)" }
        return "label:\(name ?? ""):\(title ?? "")"
    }

    var displayName: String {
        title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "Unknown source"
    }

    var isDirectlyPlayable: Bool {
        guard let rawURL = url?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawURL != "#",
              let parsed = URL(string: rawURL),
              parsed.scheme?.lowercased() == "https",
              parsed.host?.isEmpty == false else {
            return false
        }
        return behaviorHints?.notWebReady != true
            && behaviorHints?.requiresCustomHeaders != true
            && !isUnsupportedMediaURL(parsed)
    }

    func playbackSource() throws -> PlaybackSource {
        guard let rawURL = url?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty else {
            if infoHash?.isEmpty == false { throw PlaybackSourceError.torrentSourceUnsupported }
            if externalUrl?.isEmpty == false { throw PlaybackSourceError.externalSourceUnsupported }
            if ytId?.isEmpty == false { throw PlaybackSourceError.youtubeSourceUnsupported }
            throw PlaybackSourceError.missingDirectURL
        }
        guard rawURL != "#" else { throw PlaybackSourceError.addonConfigurationRequired }
        guard let parsed = URL(string: rawURL), parsed.host?.isEmpty == false else {
            throw PlaybackSourceError.invalidURL
        }
        guard parsed.scheme?.lowercased() == "https" else {
            if parsed.scheme?.lowercased() == "http" {
                throw PlaybackSourceError.insecureTransport
            }
            throw PlaybackSourceError.invalidURL
        }
        guard behaviorHints?.notWebReady != true, !isUnsupportedMediaURL(parsed) else {
            throw PlaybackSourceError.mediaFormatUnsupported
        }
        guard behaviorHints?.requiresCustomHeaders != true else {
            throw PlaybackSourceError.customHeadersUnsupported
        }
        return PlaybackSource(
            url: parsed,
            subtitles: subtitles ?? []
        )
    }

    private func isUnsupportedMediaURL(_ url: URL) -> Bool {
        ["mkv", "avi", "webm", "wmv", "flv", "mpd", "ogg", "ogv"]
            .contains(url.pathExtension.lowercased())
    }
}

struct PlaybackSource: Equatable, Sendable {
    let url: URL
    let subtitles: [StreamSubtitle]

    init(url: URL, subtitles: [StreamSubtitle] = []) {
        self.url = url
        self.subtitles = subtitles
    }
}

enum PlaybackSourceError: Error, Equatable, LocalizedError {
    case missingDirectURL
    case invalidURL
    case insecureTransport
    case customHeadersUnsupported
    case torrentSourceUnsupported
    case externalSourceUnsupported
    case youtubeSourceUnsupported
    case addonConfigurationRequired
    case mediaFormatUnsupported

    var errorDescription: String? {
        switch self {
        case .missingDirectURL: "This result has no direct media URL."
        case .invalidURL: "The addon returned an invalid media URL."
        case .insecureTransport: "Harbor blocks media sent over an insecure HTTP connection."
        case .customHeadersUnsupported: "This source needs a resolver that can attach custom request headers."
        case .torrentSourceUnsupported: "This source still needs a debrid or torrent resolver."
        case .externalSourceUnsupported: "This source opens on an external website."
        case .youtubeSourceUnsupported: "This source is a YouTube link."
        case .addonConfigurationRequired: "This addon needs configuration before it can play."
        case .mediaFormatUnsupported: "This source needs remuxing or a player with broader codec support."
        }
    }
}

struct StreamResponse: Codable, Sendable {
    let streams: [StremioStream]
}

struct CatalogResponse: Codable, Sendable {
    let metas: [StremioMeta]
}

struct MetaResponse: Codable, Sendable {
    let meta: StremioMeta
}

struct CatalogDefinition: Codable, Hashable, Sendable {
    let id: String
    let type: String
    let name: String
    let extra: [CatalogExtraDefinition]?
}

struct CatalogExtraDefinition: Codable, Hashable, Sendable {
    let name: String
    let isRequired: Bool?
    let options: [String]?
}

struct AddonResourceDescriptor: Codable, Hashable, Sendable {
    let name: String
    let types: [String]?
    let idPrefixes: [String]?
}

enum AddonResource: Codable, Hashable, Sendable {
    case name(String)
    case descriptor(AddonResourceDescriptor)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .name(value)
        } else {
            self = .descriptor(try container.decode(AddonResourceDescriptor.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .name(let value): try container.encode(value)
        case .descriptor(let value): try container.encode(value)
        }
    }
}

struct AddonBehaviorHints: Codable, Hashable, Sendable {
    let adult: Bool?
    let p2p: Bool?
    let configurable: Bool?
    let configurationRequired: Bool?
}

struct AddonManifest: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let version: String?
    let description: String?
    let logo: String?
    let background: String?
    let catalogs: [CatalogDefinition]?
    let resources: [AddonResource]?
    let types: [String]?
    let idPrefixes: [String]?
    let behaviorHints: AddonBehaviorHints?

    func accepts(resource requestedResource: String, type: String, id: String) -> Bool {
        let declaredResources = resources ?? []
        let descriptors = declaredResources.compactMap { resource -> AddonResourceDescriptor? in
            guard case .descriptor(let descriptor) = resource, descriptor.name == requestedResource else {
                return nil
            }
            return descriptor
        }
        if !descriptors.isEmpty {
            return descriptors.contains { descriptor in
                let typeMatches = descriptor.types?.contains(type) == true
                let prefixes = descriptor.idPrefixes ?? []
                return typeMatches && (prefixes.isEmpty || prefixes.contains { id.hasPrefix($0) })
            }
        }

        let hasNamedResource = declaredResources.contains { resource in
            guard case .name(let name) = resource else { return false }
            return name == requestedResource
        }
        guard hasNamedResource, types?.contains(type) == true else { return false }
        let prefixes = idPrefixes ?? []
        return prefixes.isEmpty || prefixes.contains { id.hasPrefix($0) }
    }
}

struct AddonFlags: Codable, Hashable, Sendable {
    let official: Bool?
    let protected: Bool?
}

struct StremioAddon: Codable, Identifiable, Hashable, Sendable {
    let manifest: AddonManifest
    let transportUrl: String
    let transportName: String?
    let flags: AddonFlags?

    var id: String { "\(manifest.id)|\(transportUrl)" }
}

struct AddonPersistenceState: Codable, Equatable, Sendable {
    private(set) var localAddons: [StremioAddon]
    private(set) var hiddenCloudTransportURLs: Set<String>

    init(
        localAddons: [StremioAddon] = [],
        hiddenCloudTransportURLs: Set<String> = []
    ) {
        self.localAddons = localAddons
        self.hiddenCloudTransportURLs = hiddenCloudTransportURLs
    }

    func visibleAddons(cloudAddons: [StremioAddon]) -> [StremioAddon] {
        let visibleCloud = cloudAddons.filter {
            !hiddenCloudTransportURLs.contains($0.transportUrl)
        }
        var seen = Set<String>()
        return (localAddons + visibleCloud).filter {
            seen.insert($0.transportUrl).inserted
        }
    }

    mutating func installLocal(_ addon: StremioAddon) {
        localAddons.removeAll { $0.transportUrl == addon.transportUrl }
        localAddons.append(addon)
        hiddenCloudTransportURLs.remove(addon.transportUrl)
    }

    mutating func remove(_ addon: StremioAddon, cloudAddons: [StremioAddon]) {
        localAddons.removeAll { $0.transportUrl == addon.transportUrl }
        if cloudAddons.contains(where: { $0.transportUrl == addon.transportUrl }) {
            hiddenCloudTransportURLs.insert(addon.transportUrl)
        }
    }
}

struct AddonCollectionResult: Codable, Sendable {
    let addons: [StremioAddon]
}

struct StremioUser: Codable, Equatable, Sendable {
    let id: String?
    let email: String?
    let fullname: String?
    let avatar: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case email
        case fullname
        case avatar
    }
}

struct StremioLoginResult: Codable, Sendable {
    let authKey: String
    let user: StremioUser?
}

struct APIEnvelope<Value: Decodable & Sendable>: Decodable, Sendable {
    let result: Value?
    let error: APIErrorPayload?
}

struct APIErrorPayload: Codable, Sendable {
    let message: String?
}

struct CatalogSection: Identifiable, Sendable {
    let id: String
    let title: String
    let items: [StremioMeta]
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
