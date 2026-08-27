import XCTest
@testable import HarborIOS

final class AddonPersistenceStateTests: XCTestCase {
    func testFreshCloudSnapshotReflectsServerRemoval() {
        let first = addon(id: "first", url: "https://first.example/manifest.json")
        let removed = addon(id: "removed", url: "https://removed.example/manifest.json")
        let state = AddonPersistenceState()

        XCTAssertEqual(state.visibleAddons(cloudAddons: [first, removed]).count, 2)
        XCTAssertEqual(state.visibleAddons(cloudAddons: [first]).map(\.id), [first.id])
    }

    func testHiddenCloudAddonStaysHiddenAcrossSync() throws {
        let visible = addon(id: "visible", url: "https://visible.example/manifest.json")
        let hidden = addon(id: "hidden", url: "https://hidden.example/manifest.json")
        var state = AddonPersistenceState()

        state.remove(hidden, cloudAddons: [visible, hidden])
        let restored = try JSONDecoder().decode(
            AddonPersistenceState.self,
            from: JSONEncoder().encode(state)
        )

        XCTAssertEqual(restored.visibleAddons(cloudAddons: [visible, hidden]).map(\.id), [visible.id])
    }

    func testLocalAddonWinsWhenCloudContainsSameTransportURL() {
        let local = addon(id: "local", url: "https://same.example/manifest.json")
        let cloud = addon(id: "cloud", url: "https://same.example/manifest.json")
        var state = AddonPersistenceState()

        state.installLocal(local)

        XCTAssertEqual(state.visibleAddons(cloudAddons: [cloud]).map(\.id), [local.id])
    }

    private func addon(id: String, url: String) -> StremioAddon {
        StremioAddon(
            manifest: AddonManifest(
                id: id,
                name: id,
                version: nil,
                description: nil,
                logo: nil,
                background: nil,
                catalogs: nil,
                resources: [.name("stream")],
                types: ["movie"],
                idPrefixes: ["tt"],
                behaviorHints: nil
            ),
            transportUrl: url,
            transportName: nil,
            flags: nil
        )
    }
}
