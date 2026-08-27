import XCTest
@testable import HarborIOS

final class StremioManifestTests: XCTestCase {
    func testManifestAcceptsMatchingStructuredStreamResource() throws {
        let data = Data(
            """
            {
              "id": "example.streams",
              "name": "Example",
              "resources": [
                { "name": "stream", "types": ["movie"], "idPrefixes": ["tt"] }
              ],
              "types": ["movie"]
            }
            """.utf8
        )
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: data)

        XCTAssertTrue(manifest.accepts(resource: "stream", type: "movie", id: "tt1375666"))
        XCTAssertFalse(manifest.accepts(resource: "stream", type: "series", id: "tt1375666:1:1"))
        XCTAssertFalse(manifest.accepts(resource: "stream", type: "movie", id: "tmdb:27205"))
    }

    func testStreamResponseDecodesDirectAndTorrentOffers() throws {
        let data = Data(
            """
            {
              "streams": [
                { "name": "Direct", "url": "https://cdn.example.com/video.m3u8" },
                { "name": "Torrent", "infoHash": "0123456789abcdef0123456789abcdef01234567", "fileIdx": 0 }
              ]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(StreamResponse.self, from: data)

        XCTAssertEqual(response.streams.count, 2)
        XCTAssertTrue(response.streams[0].isDirectlyPlayable)
        XCTAssertFalse(response.streams[1].isDirectlyPlayable)
    }
}
