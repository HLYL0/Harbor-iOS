import XCTest
@testable import HarborIOS

// MARK: - Phase 4 tests: adult filter, deep links.

final class AdultContentFilterTests: XCTestCase {

    func testSubstringTermsMatch() {
        XCTAssertTrue(AdultContentFilter.isAdultText("Torrentio PornHub streams"))
        XCTAssertTrue(AdultContentFilter.isAdultText("hentai catalog"))
        XCTAssertTrue(AdultContentFilter.isAdultText("OnlyFans scraper"))
        XCTAssertFalse(AdultContentFilter.isAdultText("Torrentio cached streams"))
    }

    func testWordBoundaryTermsMatch() {
        XCTAssertTrue(AdultContentFilter.isAdultText("xxx movies addon"))
        XCTAssertTrue(AdultContentFilter.isAdultText("nsfw pack"))
        // "sex" must NOT match inside a larger word (Harbor's word-boundary rule).
        XCTAssertFalse(AdultContentFilter.isAdultText("essex live tv"))
        XCTAssertFalse(AdultContentFilter.isAdultText("Sussex radio"))
    }

    func testLeetAndDiacriticNormalization() {
        XCTAssertTrue(AdultContentFilter.isAdultText("p0rn addon"), "0 → o")
        XCTAssertTrue(AdultContentFilter.isAdultText("héntai"), "NFKD strip")
        XCTAssertTrue(AdultContentFilter.isAdultText("s3x"), "3 → e")
    }

    func testBehaviorHintsAdultFlag() {
        XCTAssertTrue(AdultContentFilter.isAdultAddon(id: "org.example.clean", name: "Clean Addon", behaviorHintsAdult: true))
        XCTAssertFalse(AdultContentFilter.isAdultAddon(id: "org.example.clean", name: "Clean Addon", behaviorHintsAdult: false))
        XCTAssertFalse(AdultContentFilter.isAdultAddon(id: "org.example.clean", name: "Clean Addon", behaviorHintsAdult: nil))
    }

    func testAdultAnime() {
        XCTAssertTrue(AdultContentFilter.isAdultAnime(name: "Some Show", genres: ["Action", "Hentai"]))
        XCTAssertTrue(AdultContentFilter.isAdultAnime(name: "Erotica Special", genres: nil))
        XCTAssertFalse(AdultContentFilter.isAdultAnime(name: "Attack on Titan", genres: ["Action", "Drama"]))
    }
}

final class DeepLinkParserTests: XCTestCase {

    func testStremioDetail() {
        XCTAssertEqual(
            DeepLinkParser.parse("stremio://detail/movie/tt0133093"),
            .detail(type: "movie", id: "tt0133093", videoId: nil)
        )
        XCTAssertEqual(
            DeepLinkParser.parse("stremio://detail/series/tt0903747/tt0903747:1:1"),
            .detail(type: "series", id: "tt0903747", videoId: "tt0903747:1:1")
        )
    }

    func testHarborInstall() {
        XCTAssertEqual(
            DeepLinkParser.parse("harbor://install?manifest=https://v3-cinemeta.strem.io/manifest.json"),
            .addonInstall(manifestURL: URL(string: "https://v3-cinemeta.strem.io/manifest.json")!)
        )
    }

    func testPlainManifestURL() {
        XCTAssertEqual(
            DeepLinkParser.parse("https://example.com/manifest.json"),
            .addonInstall(manifestURL: URL(string: "https://example.com/manifest.json")!)
        )
    }

    func testWatchTogetherInvite() {
        XCTAssertEqual(
            DeepLinkParser.parse("https://app.harbor.site/?harbor-relay=wss://pub.harbor.site&harbor-room=ABC123"),
            .watchTogether(relay: "wss://pub.harbor.site", room: "ABC123")
        )
    }

    func testInvalidURLsRejected() {
        XCTAssertNil(DeepLinkParser.parse("stremio://detail/movie"))
        XCTAssertNil(DeepLinkParser.parse("stremio://evil/command"))
        XCTAssertNil(DeepLinkParser.parse("ftp://example.com/manifest.json"))
        XCTAssertNil(DeepLinkParser.parse("harbor://install?manifest=http://insecure.example.com/manifest.json"))
        XCTAssertNil(DeepLinkParser.parse("https://app.harbor.site/?harbor-room=BADD"))
        XCTAssertNil(DeepLinkParser.parse("stremio://detail/podcast/tt1234567"))
    }
}
