import XCTest
@testable import HarborIOS

final class DebridResolverTests: XCTestCase {
    func testMagnetBuildsFromUppercaseHashWithNameAndTrackers() throws {
        let magnet = try XCTUnwrap(DebridResolver.magnetURI(
            infoHash: "ABCDEF0123456789ABCDEF0123456789ABCDEF01",
            name: "Big Movie 2026"
        ))

        XCTAssertTrue(magnet.hasPrefix("magnet:?xt=urn:btih:abcdef0123456789abcdef0123456789abcdef01"))
        XCTAssertTrue(magnet.contains("dn=Big%20Movie%202026"))
        XCTAssertTrue(magnet.contains("tr=udp%3A%2F%2Ftracker.openbittorrent.com%3A80"))
    }

    func testMagnetRejectsShortOrNonHexHashes() {
        XCTAssertNil(DebridResolver.magnetURI(infoHash: "0123456789abcdef", name: nil))
        XCTAssertNil(DebridResolver.magnetURI(
            infoHash: "zzzz0123456789abcdef0123456789abcdef01234",
            name: nil
        ))
    }

    func testPreferredFileIndexIsHonoredWhenInRange() {
        let files = [
            RealDebridFile(id: 1, path: "sample.mkv", bytes: 100, selected: 0, link: nil),
            RealDebridFile(id: 2, path: "episode.mkv", bytes: 5_000_000_000, selected: 0, link: nil),
        ]

        XCTAssertEqual(DebridResolver.fileIndex(in: files, preferred: 0), 0)
    }

    func testLargestVideoFileWinsWithoutPreferredIndex() {
        let files = [
            RealDebridFile(id: 1, path: "notes.nfo", bytes: 200, selected: 0, link: nil),
            RealDebridFile(id: 2, path: "sample.mp4", bytes: 9_000_000, selected: 0, link: nil),
            RealDebridFile(id: 3, path: "movie.mp4", bytes: 4_000_000_000, selected: 0, link: nil),
        ]

        XCTAssertEqual(DebridResolver.fileIndex(in: files, preferred: nil), 2)
    }

    func testLargestFileFallsBackWhenNoVideoExtension() {
        let files = [
            RealDebridFile(id: 1, path: "data.bin", bytes: 10, selected: 0, link: nil),
            RealDebridFile(id: 2, path: "blob.dat", bytes: 999, selected: 0, link: nil),
        ]

        XCTAssertEqual(DebridResolver.fileIndex(in: files, preferred: nil), 1)
    }

    func testEmptyFileListYieldsNoIndex() {
        XCTAssertNil(DebridResolver.fileIndex(in: [], preferred: 0))
    }

    func testVideoPathDetection() {
        XCTAssertTrue(DebridResolver.isVideoPath("movie.MKV"))
        XCTAssertTrue(DebridResolver.isVideoPath("show.s02e01.mp4"))
        XCTAssertFalse(DebridResolver.isVideoPath("subs.srt"))
        XCTAssertFalse(DebridResolver.isVideoPath("notes.nfo"))
    }
}
