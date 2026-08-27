import Foundation

protocol StremioServicing: Sendable {
    func topCatalog(type: String, skip: Int) async throws -> [StremioMeta]
    func searchCatalog(type: String, query: String) async throws -> [StremioMeta]
    func metadata(type: String, id: String) async throws -> StremioMeta
    func manifest(at url: URL) async throws -> AddonManifest
    func streams(addons: [StremioAddon], type: String, id: String) async -> [AttributedStream]
    func login(email: String, password: String) async throws -> StremioLoginResult
    func currentUser(authKey: String) async throws -> StremioUser
    func logout(authKey: String) async throws
    func userAddons(authKey: String) async throws -> [StremioAddon]
}

struct AttributedStream: Identifiable, Equatable, Sendable {
    let stream: StremioStream
    let addonID: String
    let addonName: String
    let addonURL: String

    var id: String { "\(addonID)|\(stream.id)" }
}
