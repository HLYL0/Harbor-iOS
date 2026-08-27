import XCTest
@testable import HarborIOS

@MainActor
final class HomeViewModelTests: XCTestCase {
    func testSlowerPreviousSearchCannotReplaceNewestResults() async {
        let environment = AppEnvironment(service: SearchService())
        let model = HomeViewModel()

        async let oldSearch: Void = model.search("old", using: environment)
        try? await Task.sleep(nanoseconds: 20_000_000)
        await model.search("new", using: environment)
        await oldSearch

        XCTAssertEqual(model.searchResults.map(\.name), ["new"])
        XCTAssertEqual(model.activeSearchQuery, "new")
    }

    func testCompletedEmptySearchDoesNotFallBackToHomeCatalog() async {
        let environment = AppEnvironment(service: SearchService())
        let model = HomeViewModel()

        await model.search("empty", using: environment)

        XCTAssertTrue(model.searchResults.isEmpty)
        XCTAssertTrue(model.hasCompletedSearch)
        XCTAssertEqual(model.activeSearchQuery, "empty")
    }
}

private actor SearchService: StremioServicing {
    func topCatalog(type: String, skip: Int) async throws -> [StremioMeta] { [] }

    func searchCatalog(type: String, query: String) async throws -> [StremioMeta] {
        if query == "old" {
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        guard type == "movie", query != "empty" else { return [] }
        return [StremioMeta(id: query, type: "movie", name: query)]
    }

    func metadata(type: String, id: String) async throws -> StremioMeta {
        throw SearchServiceError.unused
    }

    func manifest(at url: URL) async throws -> AddonManifest {
        throw SearchServiceError.unused
    }

    func streams(addons: [StremioAddon], type: String, id: String) async -> [AttributedStream] { [] }

    func login(email: String, password: String) async throws -> StremioLoginResult {
        throw SearchServiceError.unused
    }

    func currentUser(authKey: String) async throws -> StremioUser {
        throw SearchServiceError.unused
    }

    func logout(authKey: String) async throws {}

    func userAddons(authKey: String) async throws -> [StremioAddon] { [] }
}

private enum SearchServiceError: Error {
    case unused
}
