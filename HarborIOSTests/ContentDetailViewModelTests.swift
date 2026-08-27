import XCTest
@testable import HarborIOS

@MainActor
final class ContentDetailViewModelTests: XCTestCase {
    func testChangingEpisodeClearsPreparedPlayback() async {
        let environment = AppEnvironment()
        let model = ContentDetailViewModel(
            item: StremioMeta(id: "tt123", type: "series", name: "Series")
        )
        let candidate = AttributedStream(
            stream: StremioStream(
                name: "Direct",
                url: "https://cdn.example.com/episode-one.m3u8"
            ),
            addonID: "addon",
            addonName: "Addon",
            addonURL: "https://addon.example.com/manifest.json"
        )
        let secondEpisode = StremioVideo(
            id: "tt123:1:2",
            season: 1,
            episode: 2,
            number: 2,
            released: nil,
            name: "Episode 2",
            title: nil,
            overview: nil,
            description: nil,
            thumbnail: nil
        )

        await model.play(candidate, using: environment)
        XCTAssertNotNil(model.playbackSelection)

        model.selectVideo(secondEpisode)

        XCTAssertEqual(model.selectedVideo?.id, secondEpisode.id)
        XCTAssertTrue(model.streams.isEmpty)
        XCTAssertNil(model.playbackSelection)
    }

    func testTorrentStreamWithoutDebridKeyShowsMessageInsteadOfPlaying() async {
        let environment = AppEnvironment()
        let model = ContentDetailViewModel(
            item: StremioMeta(id: "tt999", type: "movie", name: "Movie")
        )
        let candidate = AttributedStream(
            stream: StremioStream(
                name: "Torrent",
                infoHash: "0123456789abcdef0123456789abcdef01234567"
            ),
            addonID: "addon",
            addonName: "Addon",
            addonURL: "https://addon.example.com/manifest.json"
        )

        await model.play(candidate, using: environment)

        XCTAssertNil(model.playbackSelection)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.resolvingStreamID)
    }
}
