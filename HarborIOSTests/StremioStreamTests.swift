import XCTest
@testable import HarborIOS

final class StremioStreamTests: XCTestCase {
    func testDirectHTTPSStreamProducesAVPlayerSource() throws {
        let stream = StremioStream(
            name: "Cloud stream",
            title: "1080p",
            url: "https://cdn.example.com/movie/master.m3u8",
            infoHash: nil,
            subtitles: []
        )

        XCTAssertEqual(
            try stream.playbackSource(),
            PlaybackSource(url: URL(string: "https://cdn.example.com/movie/master.m3u8")!)
        )
    }

    func testTorrentOnlyStreamIsUnavailableOnIOS() {
        let stream = StremioStream(
            name: "Torrent stream",
            title: "2160p",
            url: nil,
            infoHash: "0123456789abcdef0123456789abcdef01234567",
            subtitles: []
        )

        XCTAssertThrowsError(try stream.playbackSource()) { error in
            XCTAssertEqual(error as? PlaybackSourceError, .torrentSourceUnsupported)
        }
    }

    func testKnownUnsupportedContainerIsNotAdvertisedAsDirect() {
        let stream = StremioStream(
            name: "Matroska",
            title: "1080p MKV",
            url: "https://cdn.example.com/movie.mkv",
            subtitles: []
        )

        XCTAssertFalse(stream.isDirectlyPlayable)
        XCTAssertThrowsError(try stream.playbackSource()) { error in
            XCTAssertEqual(error as? PlaybackSourceError, .mediaFormatUnsupported)
        }
    }

    func testPlainHTTPStreamIsRejected() {
        let stream = StremioStream(
            name: "Insecure stream",
            url: "http://cdn.example.com/movie/master.m3u8",
            subtitles: []
        )

        XCTAssertFalse(stream.isDirectlyPlayable)
        XCTAssertThrowsError(try stream.playbackSource()) { error in
            XCTAssertEqual(error as? PlaybackSourceError, .insecureTransport)
        }
    }

    func testHostlessHTTPSURLIsRejected() {
        let stream = StremioStream(
            name: "Malformed stream",
            url: "https:///movie/master.m3u8",
            subtitles: []
        )

        XCTAssertFalse(stream.isDirectlyPlayable)
        XCTAssertThrowsError(try stream.playbackSource()) { error in
            XCTAssertEqual(error as? PlaybackSourceError, .invalidURL)
        }
    }

    func testMPEGDashManifestIsRejected() {
        let stream = StremioStream(
            name: "DASH stream",
            url: "https://cdn.example.com/movie/manifest.mpd",
            subtitles: []
        )

        XCTAssertFalse(stream.isDirectlyPlayable)
        XCTAssertThrowsError(try stream.playbackSource()) { error in
            XCTAssertEqual(error as? PlaybackSourceError, .mediaFormatUnsupported)
        }
    }

    func testHeaderDependentStreamRequiresResolver() {
        let stream = StremioStream(
            name: "Protected stream",
            url: "https://cdn.example.com/movie/master.m3u8",
            subtitles: [],
            behaviorHints: StreamBehaviorHints(
                bingeGroup: nil,
                videoHash: nil,
                videoSize: nil,
                filename: nil,
                fileName: nil,
                notWebReady: nil,
                proxyHeaders: nil,
                headers: ["Referer": "https://addon.example.com/"]
            )
        )

        XCTAssertFalse(stream.isDirectlyPlayable)
        XCTAssertThrowsError(try stream.playbackSource()) { error in
            XCTAssertEqual(error as? PlaybackSourceError, .customHeadersUnsupported)
        }
    }

    func testExtensionlessHTTPSStreamRemainsEligible() {
        let stream = StremioStream(
            name: "Signed endpoint",
            url: "https://cdn.example.com/playback?id=42",
            subtitles: []
        )

        XCTAssertTrue(stream.isDirectlyPlayable)
    }

    func testManifestBaseURLDropsOnlyTrailingManifestComponent() throws {
        let manifest = try XCTUnwrap(URL(string: "https://addon.example.com/config/manifest.json"))

        XCTAssertEqual(
            StremioEndpoint.manifestBaseURL(manifest)?.absoluteString,
            "https://addon.example.com/config"
        )
        XCTAssertEqual(
            StremioEndpoint.streamURL(manifestURL: manifest, type: "series", id: "tt0944947:1:1")?.absoluteString,
            "https://addon.example.com/config/stream/series/tt0944947:1:1.json"
        )
    }

    func testStremioManifestURLNormalizesToHTTPS() {
        XCTAssertEqual(
            StremioEndpoint.normalizeManifestURL("stremio://addon.example.com/config")?.absoluteString,
            "https://addon.example.com/config/manifest.json"
        )
    }

    func testPlainHTTPManifestIsRejected() {
        XCTAssertNil(
            StremioEndpoint.normalizeManifestURL("http://addon.example.com/manifest.json")
        )
    }
}
