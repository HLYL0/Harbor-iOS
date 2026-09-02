import XCTest
@testable import HarborIOS

// MARK: - Phase 13 tests: M3U parsing + catch-up URL transforms (parity-critical).

final class M3UParserTests: XCTestCase {

    func testBasicPlaylist() {
        let m3u = """
        #EXTM3U
        #EXTINF:-1 tvg-id="cnn.us" tvg-logo="http://x/cnn.png" group-title="News",CNN
        http://stream.example.com/cnn.m3u8
        #EXTINF:-1 group-title="Sports",ESPN HD
        http://stream.example.com/espn.ts
        """
        let channels = M3UParser.parse(m3u, baseId: "test")
        XCTAssertEqual(channels.count, 2)
        XCTAssertEqual(channels[0].tvgId, "cnn.us")
        XCTAssertEqual(channels[0].displayName, "CNN")
        XCTAssertEqual(channels[0].groupTitle, "News")
        XCTAssertEqual(channels[0].logo, "http://x/cnn.png")
        XCTAssertEqual(channels[1].displayName, "ESPN HD")
        XCTAssertEqual(channels[1].groupTitle, "Sports")
    }

    func testStickyGroup() {
        let m3u = """
        #EXTM3U
        #EXTGRP:Movies
        #EXTINF:-1,Movie One
        http://a/1
        #EXTINF:-1,Movie Two
        http://a/2
        """
        let channels = M3UParser.parse(m3u, baseId: "t")
        XCTAssertEqual(channels[0].groupTitle, "Movies")
        XCTAssertEqual(channels[1].groupTitle, "Movies")
    }

    func testQuotedAttributeWithSpace() {
        let m3u = """
        #EXTM3U
        #EXTINF:-1 tvg-name="Channel Name With Spaces" group-title="My Group",Display Title
        http://a/1
        """
        let channels = M3UParser.parse(m3u, baseId: "t")
        XCTAssertEqual(channels[0].displayName, "Channel Name With Spaces")
        XCTAssertEqual(channels[0].groupTitle, "My Group")
    }

    func testPipeOptions() {
        let m3u = """
        #EXTM3U
        #EXTINF:-1,Channel
        http://a/1|user-agent=MyUA&referer=https://ref.example.com&cookie=session%3Dabc
        """
        let channels = M3UParser.parse(m3u, baseId: "t")
        XCTAssertEqual(channels[0].vlcoptUserAgent, "MyUA")
        XCTAssertEqual(channels[0].vlcoptReferrer, "https://ref.example.com")
        XCTAssertEqual(channels[0].cookie, "session=abc")
    }

    func testDecorativeRowsDropped() {
        let m3u = """
        #EXTM3U
        #EXTINF:-1,=====
        http://a/junk
        #EXTINF:-1,Real Channel
        http://a/real
        """
        let channels = M3UParser.parse(m3u, baseId: "t")
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].displayName, "Real Channel")
    }

    func testDividerDetection() {
        XCTAssertTrue(M3UParser.isDividerChannel("━━━━━━━━"))
        XCTAssertFalse(M3UParser.isDividerChannel("CNN International"))
    }

    func testDurationParsed() {
        let (duration, _, _) = M3UParser.parseExtinfAttributes("-1 tvg-id=\"x\",Title")
        XCTAssertEqual(duration, -1)
    }

    func testDeriveEpgUrls() {
        let urls = M3UParser.deriveEpgUrls(playlistURL: "http://server.example.com:8080/get.php?username=user&password=pass&type=m3u_plus&output=ts")
        XCTAssertEqual(urls, [
            "http://server.example.com:8080/xmltv.php?username=user&password=pass",
            "http://server.example.com:8080/get.php?username=user&password=pass&type=epg",
        ])
    }

    func testNonXtreamURLDerivesNothing() {
        XCTAssertEqual(M3UParser.deriveEpgUrls(playlistURL: "http://example.com/list.m3u"), [])
    }
}

final class CatchupBuilderTests: XCTestCase {

    private func channel(url: String, attrs: [String: String] = [:]) -> M3UChannel {
        M3UChannel(id: "x", displayName: "Ch", title: "Ch", url: url, attributes: attrs)
    }

    func testXtreamDetectionAndTimeshift() {
        let ch = channel(url: "http://host.example.com:8080/live/user/pass/12345.ts")
        XCTAssertEqual(CatchupBuilder.detectCatchupType(channel: ch), .xtream)
        // Program: 2026-09-02 14:30:00 UTC = 1762500600? Verify via known epoch: use Date math.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(year: 2026, month: 9, day: 2, hour: 14, minute: 30)
        let startMs = calendar.date(from: components)!.timeIntervalSince1970 * 1000
        let endMs = startMs + 3600 * 1000
        let url = CatchupBuilder.buildCatchupUrl(channel: ch, startMs: Int64(startMs), endMs: Int64(endMs), nowMs: Int64(startMs))
        XCTAssertEqual(url, "http://host.example.com:8080/timeshift/user/pass/60/2026-09-02:14-30/12345.ts")
    }

    func testFlussonicTransform() {
        let ch = channel(url: "http://host/channel.m3u8?token=abc", attrs: ["catchup": "fs"])
        XCTAssertEqual(CatchupBuilder.detectCatchupType(channel: ch), .flussonic)
        let url = CatchupBuilder.buildCatchupUrl(channel: ch, startMs: 1756800000000, endMs: 1756803600000, nowMs: 1756800000000)
        XCTAssertEqual(url, "http://host/channel-1756800000-3600.m3u8?token=abc")
    }

    func testFlussonicIndexStem() {
        let ch = channel(url: "http://host/mpegts.m3u8", attrs: ["catchup-type": "flussonic"])
        let url = CatchupBuilder.buildCatchupUrl(channel: ch, startMs: 1000000000, endMs: 1000003600000, nowMs: 1000000000)
        XCTAssertEqual(url, "http://host/index-1000000-3600.m3u8")
    }

    func testUtcLutcFallback() {
        let ch = channel(url: "http://host/stream.ts", attrs: ["catchup": "default"])
        let url = CatchupBuilder.buildCatchupUrl(channel: ch, startMs: 1756800000000, endMs: 1756803600000, nowMs: 1756800300000)
        XCTAssertEqual(url, "http://host/stream.ts?utc=1756800000&lutc=1756800300")
    }

    func testTemplateSourceFilled() {
        let ch = channel(
            url: "http://host/live/stream.ts",
            attrs: ["catchup": "append", "catchup-source": "http://archive.host/{utc}/{duration}.ts"]
        )
        let url = CatchupBuilder.buildCatchupUrl(channel: ch, startMs: 1756800000000, endMs: 1756803600000, nowMs: 1756800000000)
        XCTAssertEqual(url, "http://archive.host/1756800000/3600.ts")
    }

    func testStrftimeTokens() {
        let out = CatchupBuilder.fillTemplate(
            "http://host/${utc:Y}-${utc:m}-${utc:d}/${utc:H}${utc:M}.ts",
            start: 1756800000, end: 1756803600, now: 1756800000, duration: 3600
        )
        XCTAssertEqual(out, "http://host/2026-09-02/1430.ts")
    }

    func testCatchupDaysNotEnforced() {
        // catchup-days attr must NOT gate URL building (Harbor parity — FACT).
        let ch = channel(url: "http://host/live/u/p/9.ts", attrs: ["catchup-days": "0"])
        XCTAssertNotNil(CatchupBuilder.buildCatchupUrl(channel: ch, startMs: 1, endMs: 3601000, nowMs: 1))
    }
}
