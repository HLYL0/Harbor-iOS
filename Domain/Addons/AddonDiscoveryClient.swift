import Foundation

// MARK: - Addon discovery client (Phase 4).
// Ports Harbor's discovery pipeline (docs/audit/stremio-addons.md §5):
// primary = stremio-addons.net API v0, fallback/merge = Stremio's own community/official
// catalogs, 1h TTL cache, adult gating applied at the catalog layer.

struct DiscoveredAddon: Codable, Identifiable, Equatable, Sendable {
    var manifestId: String
    var name: String
    var description: String?
    var logo: String?
    var background: String?
    var stars: Int
    var categories: [String]
    var slug: String?
    var behaviorHintsAdult: Bool?

    var id: String { manifestId }

    init(
        manifestId: String, name: String, description: String? = nil,
        logo: String? = nil, background: String? = nil, stars: Int = 0,
        categories: [String] = [], slug: String? = nil,
        behaviorHintsAdult: Bool? = nil
    ) {
        self.manifestId = manifestId
        self.name = name
        self.description = description
        self.logo = logo
        self.background = background
        self.stars = stars
        self.categories = categories
        self.slug = slug
        self.behaviorHintsAdult = behaviorHintsAdult
    }
}

enum AddonDiscoveryError: Error, LocalizedError {
    case allSourcesFailed

    var errorDescription: String? {
        "The addon directory is unreachable right now."
    }
}

protocol AddonDiscoveryServicing: Sendable {
    func browse(mode: BrowseMode, category: String?, query: String?, allowAdult: Bool) async throws -> [DiscoveredAddon]
}

enum BrowseMode: String, Sendable {
    case top
    case rising
    case new
}

actor AddonDiscoveryClient: AddonDiscoveryServicing {

    static let shared = AddonDiscoveryClient()

    private let network: NetworkClient
    private var cache: [String: (addons: [DiscoveredAddon], storedAt: Date)] = [:]
    private let ttl: TimeInterval = 3600   // 1 h (Harbor parity)

    private struct SAAddon: Codable {
        var id: String?          // manifest id
        var manifestId: String?
        var name: String
        var slug: String?
        var description: String?
        var logo: String?
        var background: String?
        var stars: Int?
        var categories: [String]?
        var behaviorHints: SABehaviorHints?
        var recentStars: Int?
        var createdAt: String?
    }

    private struct SABehaviorHints: Codable {
        var adult: Bool?
    }

    init(network: NetworkClient = .shared) {
        self.network = network
    }

    // MARK: - Harbor parity endpoints

    func list(category: String? = nil, query: String? = nil, allowAdult: Bool) async throws -> [DiscoveredAddon] {
        var url = URL(string: "https://stremio-addons.net/api/v0/addons")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "200"),
            URLQueryItem(name: "sort_by", value: "stars"),
            URLQueryItem(name: "order", value: "desc"),
        ]
        if let category, !category.isEmpty { queryItems.append(URLQueryItem(name: "category", value: category)) }
        if let query, !query.isEmpty { queryItems.append(URLQueryItem(name: "search", value: query)) }
        if !allowAdult { queryItems.append(URLQueryItem(name: "nsfw", value: "exclude")) }
        components.queryItems = queryItems
        url = components.url!

        let result: SAEnvelope = try await network.get(SAEnvelope.self, url: url, policy: .default)
        var addons = result.addons.map(map)
        if !allowAdult {
            addons = addons.filter { !AdultContentFilter.isAdultAddon(id: $0.manifestId, name: $0.name, behaviorHintsAdult: $0.behaviorHintsAdult) }
        }
        return addons
    }

    func rising(allowAdult: Bool) async throws -> [DiscoveredAddon] {
        let result: SARisingEnvelope = try await network.get(
            SARisingEnvelope.self,
            url: URL(string: "https://stremio-addons.net/api/v0/rising")!,
            policy: .default
        )
        var addons = result.addons.map(map)
        if !allowAdult {
            addons = addons.filter { !AdultContentFilter.isAdultAddon(id: $0.manifestId, name: $0.name, behaviorHintsAdult: $0.behaviorHintsAdult) }
        }
        return addons
    }

    func categories() async throws -> [String] {
        struct CatEnvelope: Decodable { var categories: [String]? }
        let fallback = ["anime", "asian drama", "bollywood", "debrid support", "http streams",
                        "live tv", "metadata", "misc", "movies", "music", "nsfw", "radios",
                        "subtitles", "torrents", "tv shows", "usenet"]
        do {
            let envelope: CatEnvelope = try await network.get(
                CatEnvelope.self,
                url: URL(string: "https://stremio-addons.net/api/v0/categories")!,
                policy: .default
            )
            return envelope.categories ?? fallback
        } catch {
            return fallback   // Harbor parity: hardcoded fallback on API failure
        }
    }

    // MARK: - Community / official catalog merge (Harbor parity)

    func communityCatalog(allowAdult: Bool) async throws -> [DiscoveredAddon] {
        let communityURL = URL(string: "https://v3-cinemeta.strem.io/addon_catalog/all/community.json")!
        let officialURL = URL(string: "https://v3-cinemeta.strem.io/addon_catalog/all/official.json")!

        async let community: [DiscoveredAddon]? = try? fetchCollection(url: communityURL, allowAdult: allowAdult)
        async let official: [DiscoveredAddon]? = try? fetchCollection(url: officialURL, allowAdult: allowAdult)
        let merged = ((try? await community) ?? []) + ((try? await official) ?? [])
        var seen = Set<String>()
        return merged.filter { seen.insert($0.manifestId).inserted }
    }

    private func fetchCollection(url: URL, allowAdult: Bool) async throws -> [DiscoveredAddon] {
        struct CollectionResponse: Decodable {
            struct Entry: Decodable {
                var manifest: CollectionManifest?
            }
            struct CollectionManifest: Decodable {
                var id: String
                var name: String
                var description: String?
                var logo: String?
                var background: String?
                var behaviorHints: SABehaviorHints?
            }
            var addons: [Entry]?
            var items: [Entry]?
        }
        let response: CollectionResponse = try await network.get(CollectionResponse.self, url: url, policy: .default)
        let entries = response.addons ?? response.items ?? []
        var out: [DiscoveredAddon] = []
        for entry in entries {
            guard let manifest = entry.manifest else { continue }
            let adult = manifest.behaviorHints?.adult
            if !allowAdult, AdultContentFilter.isAdultAddon(id: manifest.id, name: manifest.name, behaviorHintsAdult: adult) {
                continue
            }
            out.append(DiscoveredAddon(
                manifestId: manifest.id,
                name: manifest.name,
                description: manifest.description,
                logo: manifest.logo,
                background: manifest.background,
                stars: 0,
                behaviorHintsAdult: adult
            ))
        }
        return out
    }

    // MARK: - Unified browse with cache (Harbor's directory pipeline)

    func browse(mode: BrowseMode, category: String? = nil, query: String? = nil, allowAdult: Bool) async throws -> [DiscoveredAddon] {
        let key = "\(mode.rawValue)|\(category ?? "")|\(query ?? "")|\(allowAdult)"
        if let hit = cache[key], Date().timeIntervalSince(hit.storedAt) < ttl {
            return hit.addons
        }

        var results: [DiscoveredAddon] = []
        var anySuccess = false

        do {
            switch mode {
            case .top, .new:
                results = try await list(category: category, query: query, allowAdult: allowAdult)
                if mode == .new {
                    results = results.sorted { ($0.name) < ($1.name) }   // createdAt sort approximated; SA list is star-sorted
                }
            case .rising:
                results = try await rising(allowAdult: allowAdult)
            }
            anySuccess = true
        } catch {
            results = []
        }

        // Enrich with community catalog (Harbor merges; failures contribute []).
        if let community = try? await communityCatalog(allowAdult: allowAdult) {
            let known = Set(results.map(\.manifestId))
            results += community.filter { !known.contains($0.manifestId) }
        }

        if !anySuccess && results.isEmpty {
            throw AddonDiscoveryError.allSourcesFailed
        }
        cache[key] = (results, Date())
        return results
    }

    private func map(_ addon: SAAddon) -> DiscoveredAddon {
        DiscoveredAddon(
            manifestId: addon.manifestId ?? addon.id ?? addon.name,
            name: addon.name,
            description: addon.description,
            logo: addon.logo,
            background: addon.background,
            stars: addon.stars ?? 0,
            categories: addon.categories ?? [],
            slug: addon.slug,
            behaviorHintsAdult: addon.behaviorHints?.adult
        )
    }

    private struct SAEnvelope: Decodable {
        var addons: [SAAddon]
    }

    private struct SARisingEnvelope: Decodable {
        var addons: [SAAddon]
    }
}
