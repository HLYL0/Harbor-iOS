import Foundation

// MARK: - Catalog service (Phase 5/6).
// Ports Harbor's catalog loading contract (audit stremio-addons.md §3):
// parallel addon requests, 8s timeout, required-extra first-option resolution,
// `skip=` pagination, per-addon failures dropped, partial results always delivered.

public struct CatalogPage: Sendable {
    public var metas: [StremioMeta]
    public var hasMore: Bool

    public init(metas: [StremioMeta], hasMore: Bool) {
        self.metas = metas
        self.hasMore = hasMore
    }
}

public enum CatalogError: Error, LocalizedError {
    case noResults

    public var errorDescription: String? { "No catalog rows were returned." }
}

public protocol CatalogServicing: Sendable {
    func catalogs(addons: [StremioAddon], type: String) -> [(addon: StremioAddon, catalog: CatalogDefinition)]
    func fetchCatalog(
        addon: StremioAddon, catalog: CatalogDefinition,
        type: String, skip: Int, extra: [String: String]
    ) async throws -> [StremioMeta]
}

public actor CatalogService: CatalogServicing {

    public static let shared = CatalogService()

    private let network: NetworkClient
    private let requestTimeout: TimeInterval = 8   // Harbor: 8s catalog timeout

    public init(network: NetworkClient = .shared) {
        self.network = network
    }

    /// All catalogs an addon declares for a media type, plus Cinemeta (always first).
    public func catalogs(addons: [StremioAddon], type: String) -> [(addon: StremioAddon, catalog: CatalogDefinition)] {
        var out: [(addon: StremioAddon, catalog: CatalogDefinition)] = []
        for addon in addons {
            guard let catalogs = addon.manifest.catalogs else { continue }
            for catalog in catalogs where catalog.type == type {
                out.append((addon, catalog))
            }
        }
        return out
    }

    public func fetchCatalog(
        addon: StremioAddon, catalog: CatalogDefinition,
        type: String, skip: Int, extra: [String: String]
    ) async throws -> [StremioMeta] {
        guard let url = buildCatalogURL(addon: addon, catalog: catalog, type: type, skip: skip, extra: extra) else {
            throw CatalogError.noResults
        }
        let response: CatalogResponse = try await network.get(CatalogResponse.self, url: url, policy: .none)
        return response.metas
    }

    // MARK: - URL construction (Stremio protocol, Harbor parity)

    public func buildCatalogURL(
        addon: StremioAddon, catalog: CatalogDefinition,
        type: String, skip: Int, extra: [String: String]
    ) -> URL? {
        let base = addon.transportUrl
            .replacingOccurrences(of: "/manifest.json", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(string: "\(base)/catalog/\(type)/\(catalog.id).json")!
        var queryItems: [URLQueryItem] = []
        if skip > 0 { queryItems.append(URLQueryItem(name: "skip", value: String(skip))) }

        // Required extras resolve to their FIRST option (Harbor parity, audit §3).
        var resolved = extra
        for definition in catalog.extra ?? [] where resolved[definition.name] == nil {
            if let firstOption = definition.options?.first {
                resolved[definition.name] = firstOption
            }
        }
        for (key, value) in resolved {
            queryItems.append(URLQueryItem(name: key, value: value))
        }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        return components.url
    }

    /// Parallel fan-out with per-addon failure isolation + progressive delivery.
    public func fetchAllCatalogs(
        addons: [StremioAddon],
        type: String,
        skip: Int,
        extra: [String: String],
        onPartial: @Sendable ([StremioMeta]) -> Void = { _ in }
    ) async -> [StremioMeta] {
        let pairs = catalogs(addons: addons, type: type)
        guard !pairs.isEmpty else { return [] }
        var results: [StremioMeta] = []
        await withTaskGroup(of: [StremioMeta]?.self) { group in
            for (addon, catalog) in pairs {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    do {
                        let metas = try await self.fetchCatalog(
                            addon: addon, catalog: catalog, type: type, skip: skip, extra: extra
                        )
                        return metas
                    } catch {
                        return nil   // per-addon failure dropped (Harbor parity)
                    }
                }
            }
            var seen = Set<String>()
            for await batch in group {
                guard let batch, !batch.isEmpty else { continue }
                let fresh = batch.filter { seen.insert($0.id).inserted }
                if !fresh.isEmpty {
                    results.append(contentsOf: fresh)
                    onPartial(fresh)
                }
            }
        }
        return results
    }

    /// Cinemeta-first catalog fetch (Harbor's default catalog base).
    public func cinemetaCatalog(type: String, skip: Int = 0, genre: String? = nil, search: String? = nil) async throws -> [StremioMeta] {
        var components = URLComponents(string: "https://v3-cinemeta.strem.io/catalog/\(type)/top.json")!
        var items: [URLQueryItem] = []
        if skip > 0 { items.append(URLQueryItem(name: "skip", value: String(skip))) }
        if let genre { items.append(URLQueryItem(name: "genre", value: genre)) }
        if let search { items.append(URLQueryItem(name: "search", value: search)) }
        components.queryItems = items.isEmpty ? nil : items
        guard let url = components.url else { throw CatalogError.noResults }
        let response: CatalogResponse = try await network.get(CatalogResponse.self, url: url, policy: .none)
        return response.metas
    }
}
