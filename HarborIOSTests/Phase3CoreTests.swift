import XCTest
@testable import HarborIOS

// MARK: - Phase 3 unit tests: settings store, migrations, privacy blocklist, networking, cache.

final class SettingsStoreTests: XCTestCase {

    func testDefaultsWhenNoFile() async {
        let store = SettingsStore(fileManager: .default)
        let settings = await store.load(profileID: "test-profile-no-file")
        XCTAssertEqual(settings.activeProfileId, "guest")
        XCTAssertEqual(settings.uiLanguage, "en")
        XCTAssertEqual(settings.playerEngine, "auto")
        XCTAssertTrue(settings.stremioDeeplinkInstall)
        XCTAssertFalse(settings.showAdultAddons)
        XCTAssertFalse(settings.subtitleAutoSync)
    }

    func testRoundTrip() async throws {
        let store = SettingsStore(fileManager: .default)
        var settings = AppSettings()
        settings.uiLanguage = "ar"
        settings.playerEngine = "mpv"
        settings.subProvidersEnabled = ["wyzie", "jimaku"]
        settings.homeRowsOrder = ["continue-watching", "top10"]

        try await store.save(settings, profileID: "round-trip-profile")
        let loaded = await store.load(profileID: "round-trip-profile")

        XCTAssertEqual(loaded.uiLanguage, "ar")
        XCTAssertEqual(loaded.playerEngine, "mpv")
        XCTAssertEqual(loaded.subProvidersEnabled, ["wyzie", "jimaku"])
        XCTAssertEqual(loaded.homeRowsOrder, ["continue-watching", "top10"])
    }

    func testMigrationFlagsRunOnce() async {
        // Simulate a pre-migration blob: no trackerBlockingEnabled key at all.
        let store = SettingsStore(fileManager: .default)
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Harbor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("settings-migration-profile.json")
        let raw: [String: Any] = ["activeProfileId": "guest"]
        try? JSONSerialization.data(withJSONObject: raw).write(to: url)

        let settings = await store.load(profileID: "migration-profile")
        XCTAssertTrue(settings.trackerBlockingEnabled, "migration must default tracker blocking ON")
        XCTAssertTrue(settings.stremioDeeplinkInstall, "migration must default deep-link install ON")
    }

    func testSanitization() {
        var settings = AppSettings()
        settings.playerEngine = "html5"  // not a valid iOS engine
        settings.uiLanguage = "xx"
        settings.subDelayMs = 999_999
        settings.subProvidersEnabled = ["wyzie", "bogus"]

        SettingsMigrator.sanitize(&settings)
        XCTAssertEqual(settings.playerEngine, "auto")
        XCTAssertEqual(settings.uiLanguage, "en")
        XCTAssertEqual(settings.subDelayMs, 0)
        XCTAssertEqual(settings.subProvidersEnabled, ["wyzie"])
    }
}

final class PrivacyBlocklistTests: XCTestCase {

    func testBlocksKnownTrackers() {
        let blocked = [
            "https://www.google-analytics.com/collect",
            "https://connect.facebook.net/en_US/fbevents.js",
            "https://analytics.tiktok.com/i18n/pixel/events.js",
            "https://mc.yandex.ru/metrika/watch.js",
            "https://doubleclick.net/pagead/id",
            "https://cdn.taboola.com/libtrc/x/loader.js",
        ]
        for urlString in blocked {
            let url = URL(string: urlString)!
            XCTAssertTrue(PrivacyBlocklist.isBlocked(url), "\(urlString) must be blocked")
        }
    }

    func testAllowsLegitimateTraffic() {
        let allowed = [
            "https://v3-cinemeta.strem.io/manifest.json",
            "https://api.real-debrid.com/rest/1.0/user",
            "https://api.strem.io/api/login",
            "https://api.aniskip.com/v2/skip-times/1/1",
            "https://api.trakt.tv/users/me",
            "https://pub.harbor.site/health",
        ]
        for urlString in allowed {
            let url = URL(string: urlString)!
            XCTAssertFalse(PrivacyBlocklist.isBlocked(url), "\(urlString) must be allowed")
        }
    }

    func testSuffixMatching() {
        let url = URL(string: "https://region1.google-analytics.com/g/collect")!
        XCTAssertTrue(PrivacyBlocklist.isBlocked(url))
    }
}

final class NetworkClientTests: XCTestCase {

    private actor ScriptedTransport: HTTPTransport {
        private var script: [Result<Int, Int>]  // status codes per attempt

        init(script: [Int]) {
            self.script = script.map { .success($0) }
        }

        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            guard !script.isEmpty else {
                throw NetworkClientError.invalidResponse
            }
            let status = script.removeFirst()
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (Data(), response)
        }
    }

    func testRetriesThenSucceeds() async throws {
        let transport = ScriptedTransport(script: [503, 200])
        let client = NetworkClient(transport: transport)
        let request = URLRequest(url: URL(string: "https://example.com/api")!)

        let (_, response) = try await client.data(for: request, policy: .default)
        XCTAssertEqual(response.statusCode, 200)
    }

    func testNonRetryableStatusThrowsImmediately() async {
        let transport = ScriptedTransport(script: [404, 200])
        let client = NetworkClient(transport: transport)
        let request = URLRequest(url: URL(string: "https://example.com/api")!)

        do {
            _ = try await client.data(for: request, policy: .default)
            XCTFail("404 must not be retried")
        } catch let NetworkClientError.httpStatus(code) {
            XCTAssertEqual(code, 404)
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func testBlockedURLNeverReachesTransport() async {
        let transport = ScriptedTransport(script: [200])
        let client = NetworkClient(transport: transport)
        let request = URLRequest(url: URL(string: "https://www.google-analytics.com/collect")!)

        do {
            _ = try await client.data(for: request, policy: .none)
            XCTFail("tracker must be blocked")
        } catch let NetworkClientError.blocked(host) {
            XCTAssertTrue(host.contains("google-analytics"))
        } catch {
            XCTFail("wrong error type: \(error)")
        }
        let count = await client.blockedRequestCount
        XCTAssertEqual(count, 1)
    }

    func testBackoffIsBounded() {
        let policy = RetryPolicy(baseDelay: 1, maxDelay: 4)
        let client = NetworkClient()
        let d = client.delaySeconds(attempt: 10, policy: policy)
        XCTAssertTrue(d >= 0 && d <= 4, "delay \(d) must be clamped to maxDelay")
    }
}

final class AppCacheTests: XCTestCase {

    func testRoundTripAndTTL() async {
        let cache = AppCache()
        cache.removeAll(namespace: "test-cache")
        struct Payload: Codable, Equatable { let value: Int }
        cache.set(Payload(value: 42), key: "k1", namespace: "test-cache", ttl: 60)
        XCTAssertEqual(cache.get(Payload.self, key: "k1", namespace: "test-cache")?.value, 42)

        // Expired entry must vanish.
        cache.set(Payload(value: 7), key: "k2", namespace: "test-cache", ttl: -1)
        XCTAssertNil(cache.get(Payload.self, key: "k2", namespace: "test-cache"))
        cache.removeAll(namespace: "test-cache")
    }

    func testRemove() {
        let cache = AppCache()
        cache.removeAll(namespace: "test-cache-remove")
        struct Payload: Codable { let v: Int }
        cache.set(Payload(v: 1), key: "x", namespace: "test-cache-remove")
        XCTAssertNotNil(cache.get(Payload.self, key: "x", namespace: "test-cache-remove"))
        cache.remove(key: "x", namespace: "test-cache-remove")
        XCTAssertNil(cache.get(Payload.self, key: "x", namespace: "test-cache-remove"))
    }
}
