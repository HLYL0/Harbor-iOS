import XCTest
@testable import HarborIOS

/// Ports of the harbor-core scoring.rs unit tests (scoring.rs:1306-1870, all 22 pass against
/// the Rust binary) plus additional edge vectors. Every exact score asserted here is the
/// value the Rust reference implementation produces for the same input.
final class ScoringTests: XCTestCase {

    // MARK: - Fixtures

    /// scoring.rs:1310-1346 `base_parsed()` — 1080p WEB-DL, codec Other, audio 2ch,
    /// addonId "test" / addonName "test-addon", everything else default.
    private func baseParsed(
        resolution: Resolution = .p1080,
        source: Source = .webDl,
        hdrFormat: HdrFormat? = nil,
        codec: Codec = .other,
        audioCodec: AudioCodec = .other,
        channels: Int = 2,
        addonName: String = "test-addon",
        addonId: String = "test"
    ) -> ParsedStream {
        ParsedStream(
            stream: EngineStream(addonId: addonId, addonName: addonName),
            parsedTitle: "",
            resolution: resolution,
            hdrFormat: hdrFormat,
            codec: codec,
            source: source,
            audio: AudioInfo(codec: audioCodec, channels: channels),
            audioLanguages: [],
            size: nil,
            seeders: nil,
            cached: [:],
            inLibrary: [:],
            container: nil,
            releaseGroup: nil,
            releaseGroupNormalized: nil,
            remux: false,
            edition: nil,
            year: nil,
            yearRange: nil,
            season: nil,
            episode: nil,
            seasonPack: false,
            discIndex: nil,
            repackIteration: 0,
            proper: false,
            hardcoded: false,
            animeHash: nil,
            scamScore: 0
        )
    }

    /// scoring.rs:1348-1350 `empty_corpus()`.
    private func emptyCorpus() -> CorpusStats { CorpusStats() }

    /// scoring.rs:1352-1354 `empty_opts()`.
    private func opts(
        activeDebrids: [String] = [],
        preferredLanguages: [String] = [],
        releaseDate: String? = nil,
        mediaKind: String? = nil,
        runtimeMinutes: Int? = nil,
        respectAddonOrder: Bool = false,
        preferredReleaseGroup: String? = nil,
        bandwidthMbps: Double? = nil,
        preferSingleAudioTrack: Bool = false,
        preferAddonId: String? = nil
    ) -> ScoreOptions {
        ScoreOptions(
            activeDebrids: activeDebrids,
            preferredLanguages: preferredLanguages,
            releaseDate: releaseDate,
            mediaKind: mediaKind,
            runtimeMinutes: runtimeMinutes,
            inTheaters: false,
            respectAddonOrder: respectAddonOrder,
            preferredReleaseGroup: preferredReleaseGroup,
            bandwidthMbps: bandwidthMbps,
            preferSingleAudioTrack: preferSingleAudioTrack,
            preferAddonId: preferAddonId
        )
    }

    private func scored(_ parsed: ParsedStream, score: Double, tier: Tier) -> ScoredStream {
        ScoredStream(parsed: parsed, score: score, reasons: [], tier: tier)
    }

    /// scoring.rs:1370-1375 `days_ago_iso()` — release date N days in the past (date-only, UTC).
    private func isoDaysAgo(_ days: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date().addingTimeInterval(-days * 86_400))
    }

    private func signals(_ scored: ScoredStream) -> [String] {
        scored.reasons.map(\.signal)
    }

    // MARK: - Exact-score vectors (Rust scoring.rs tests)

    /// scoring.rs:1437 — 4K + HDR10 + HEVC + Atmos 8ch → 36.0, tier 4K_HDR.
    func testScore4KHDR10HEVCAtmos8Channels() {
        let parsed = baseParsed(
            resolution: .uhd, hdrFormat: .hdr10, codec: .hevc,
            audioCodec: .atmos, channels: 8
        )
        let result = Scoring.scoreStream(parsed: parsed, opts: opts(), corpus: emptyCorpus())

        XCTAssertEqual(result.score, 36.0)
        XCTAssertEqual(result.tier, .uhdHdr)
        let names = signals(result)
        XCTAssertTrue(names.contains("4K"))
        XCTAssertTrue(names.contains("HDR10"))
        XCTAssertTrue(names.contains("HEVC"))
        XCTAssertTrue(names.contains("Atmos"))
        XCTAssertTrue(names.contains("8.0 channels"))
    }

    /// scoring.rs:1462 — 4K + DV+HDR10 → 31.0 = 25 + 6, tier 4K_DV.
    func testScore4KDVHDR10() {
        let parsed = baseParsed(resolution: .uhd, hdrFormat: .dvHdr10)
        let result = Scoring.scoreStream(parsed: parsed, opts: opts(), corpus: emptyCorpus())

        XCTAssertEqual(result.score, 31.0)
        XCTAssertEqual(result.tier, .uhdDv)
        let dv = result.reasons.first { $0.signal == "DV+HDR10" }
        XCTAssertEqual(dv?.delta, 6.0)
    }

    /// scoring.rs:1478 — cached rd + MediaFusion → 88.0 = 60 + 20 + 8.
    func testCachedRDMediaFusionStrongAddon() {
        var parsed = baseParsed(addonName: "MediaFusion")
        parsed.cached["rd"] = true
        let result = Scoring.scoreStream(
            parsed: parsed,
            opts: opts(activeDebrids: ["rd"]),
            corpus: emptyCorpus()
        )

        XCTAssertEqual(result.score, 88.0)
        let names = signals(result)
        XCTAssertTrue(names.contains("cached"))
        XCTAssertTrue(names.contains("strong-addon"))
        XCTAssertFalse(names.contains("easynews-direct"))
    }

    /// scoring.rs:1495 — Easynews+ addon → 84.0 = 60 + 20 + 4, signal "easynews-direct".
    func testEasynewsAddonTreatedAsCachedAlternative() {
        let parsed = baseParsed(addonName: "Easynews+")
        let result = Scoring.scoreStream(parsed: parsed, opts: opts(), corpus: emptyCorpus())

        XCTAssertTrue(signals(result).contains("easynews-direct"))
        XCTAssertEqual(result.score, 84.0)
    }

    /// scoring.rs:1505 — CAM 720p → −72.0 = 8 − 80, tier ROUGH.
    func testCAMSourcePenalizedAndMarkedRough() {
        let parsed = baseParsed(resolution: .p720, source: .cam)
        let result = Scoring.scoreStream(parsed: parsed, opts: opts(), corpus: emptyCorpus())

        XCTAssertEqual(result.score, -72.0)
        XCTAssertEqual(result.tier, .rough)
    }

    /// scoring.rs:1515 — seeders: 5→20.0 (no boost); 0+hash→−8.0 (both zero-seeder signals);
    /// 95→29.0 (+9); 500→30.0 (+10 cap).
    func testSeederScoring() {
        var p5 = baseParsed()
        p5.seeders = 5
        p5.stream.infoHash = "abc"
        XCTAssertEqual(Scoring.scoreStream(parsed: p5, opts: opts(), corpus: emptyCorpus()).score, 20.0)

        var p0 = baseParsed()
        p0.seeders = 0
        p0.stream.infoHash = "abc"
        let zero = Scoring.scoreStream(parsed: p0, opts: opts(), corpus: emptyCorpus())
        XCTAssertEqual(zero.score, -8.0)
        let zeroSignals = signals(zero)
        XCTAssertTrue(zeroSignals.contains("zero-seeders-stale-meta"))
        XCTAssertTrue(zeroSignals.contains("zero-seeders-soft"))

        var p95 = baseParsed()
        p95.seeders = 95
        XCTAssertEqual(Scoring.scoreStream(parsed: p95, opts: opts(), corpus: emptyCorpus()).score, 29.0)

        var p500 = baseParsed()
        p500.seeders = 500
        XCTAssertEqual(Scoring.scoreStream(parsed: p500, opts: opts(), corpus: emptyCorpus()).score, 30.0)
    }

    /// scoring.rs:1543 — preferred "en": English→32.0 (+12); French→6.0 (−14);
    /// empty→17.0 (−3); Multi→24.0 (+4).
    func testPreferredLanguageScoring() {
        var english = baseParsed()
        english.audioLanguages = ["English"]
        let enOpts = opts(preferredLanguages: ["en"])
        XCTAssertEqual(Scoring.scoreStream(parsed: english, opts: enOpts, corpus: emptyCorpus()).score, 32.0)

        var french = baseParsed()
        french.audioLanguages = ["French"]
        XCTAssertEqual(Scoring.scoreStream(parsed: french, opts: enOpts, corpus: emptyCorpus()).score, 6.0)

        let silent = baseParsed()
        XCTAssertEqual(Scoring.scoreStream(parsed: silent, opts: enOpts, corpus: emptyCorpus()).score, 17.0)

        var multi = baseParsed()
        multi.audioLanguages = ["Multi"]
        XCTAssertEqual(Scoring.scoreStream(parsed: multi, opts: enOpts, corpus: emptyCorpus()).score, 24.0)
    }

    /// scoring.rs:1779 — PROPER → 21.0 (+1.0); REPACK1 → 21.0 (+1.0); REPACK5 → 22.0 (+2.0).
    func testProperRepackIterationLogic() {
        var proper = baseParsed()
        proper.proper = true
        let properResult = Scoring.scoreStream(parsed: proper, opts: opts(), corpus: emptyCorpus())
        XCTAssertEqual(properResult.score, 21.0)
        XCTAssertEqual(properResult.reasons.first { $0.signal == "PROPER" }?.delta, 1.0)

        var repack1 = baseParsed()
        repack1.repackIteration = 1
        let r1 = Scoring.scoreStream(parsed: repack1, opts: opts(), corpus: emptyCorpus())
        XCTAssertEqual(r1.score, 21.0)
        XCTAssertEqual(r1.reasons.first { $0.signal == "REPACK1" }?.delta, 1.0)

        var repack5 = baseParsed()
        repack5.repackIteration = 5
        let r5 = Scoring.scoreStream(parsed: repack5, opts: opts(), corpus: emptyCorpus())
        XCTAssertEqual(r5.score, 22.0)
        XCTAssertEqual(r5.reasons.first { $0.signal == "REPACK5" }?.delta, 2.0)
    }

    /// scoring.rs:1803 — trusted FLUX + remux + BluRay → 25.0 = 20 + 2 + 3.
    func testTrustedReleaseGroupAndRemuxBonuses() {
        var parsed = baseParsed(source: .bluRay)
        parsed.releaseGroupNormalized = "FLUX"
        parsed.remux = true
        let result = Scoring.scoreStream(parsed: parsed, opts: opts(), corpus: emptyCorpus())
        XCTAssertEqual(result.score, 25.0)
    }

    /// scoring.rs:1813 — "HDCAM" in title, 1080p WEB-DL → −80.0 = 20 − 100.
    func testCamInFilenamePenaltyFor1080pWord() {
        var parsed = baseParsed()
        parsed.stream.title = "Some.Movie.1080p.WEB-DL.HDCAM.mkv"
        let result = Scoring.scoreStream(parsed: parsed, opts: opts(), corpus: emptyCorpus())

        XCTAssertEqual(result.score, -80.0)
        XCTAssertTrue(signals(result).contains("title-says-hires-filename-says-cam"))
    }

    /// scoring.rs:1825 — addon priority: p0→32.0, p2→24.0, p5→20.0, none→20.0.
    func testAddonPriorityBonusDecaysWithPosition() {
        var p0 = baseParsed()
        p0.stream.addonPriority = 0
        XCTAssertEqual(Scoring.scoreStream(parsed: p0, opts: opts(), corpus: emptyCorpus()).score, 32.0)

        var p2 = baseParsed()
        p2.stream.addonPriority = 2
        XCTAssertEqual(Scoring.scoreStream(parsed: p2, opts: opts(), corpus: emptyCorpus()).score, 24.0)

        var p5 = baseParsed()
        p5.stream.addonPriority = 5
        XCTAssertEqual(Scoring.scoreStream(parsed: p5, opts: opts(), corpus: emptyCorpus()).score, 20.0)

        let none = baseParsed()
        XCTAssertEqual(Scoring.scoreStream(parsed: none, opts: opts(), corpus: emptyCorpus()).score, 20.0)
    }

    /// scoring.rs:1570 — tier edges.
    func testTierAssignmentEdgeCases() {
        var parsed = baseParsed(resolution: .uhd, hdrFormat: .dv)
        XCTAssertEqual(Scoring.tierOf(parsed: parsed), .uhdDv)

        parsed.hdrFormat = .hdr10
        XCTAssertEqual(Scoring.tierOf(parsed: parsed), .uhdHdr)

        parsed.hdrFormat = nil
        XCTAssertEqual(Scoring.tierOf(parsed: parsed), .uhd)

        parsed.resolution = .p1080
        XCTAssertEqual(Scoring.tierOf(parsed: parsed), .p1080)
        parsed.hdrFormat = .hlg
        XCTAssertEqual(Scoring.tierOf(parsed: parsed), .p1080Hdr)

        parsed.resolution = .p720
        parsed.hdrFormat = nil
        XCTAssertEqual(Scoring.tierOf(parsed: parsed), .p720)

        parsed.resolution = .p480
        XCTAssertEqual(Scoring.tierOf(parsed: parsed), .sd)

        parsed.source = .scr
        XCTAssertEqual(Scoring.tierOf(parsed: parsed), .rough)

        parsed.source = .cam
        parsed.resolution = .uhd
        parsed.hdrFormat = .dv
        XCTAssertEqual(Scoring.tierOf(parsed: parsed), .rough)
    }

    /// scoring.rs:1378 — dominated pool at day 50: TS stays boosted (+75), fake 4K WEBRip penalized (−45).
    func testFreshDominatedWindowProtectsTheaterPast30Days() {
        let corpus = CorpusStats(
            daysSinceRelease: 50.0,
            trustedTrackedFraction: 0.0,
            theaterCaptureFraction: 0.8,
            webishFraction: 0.1,
            trustedTrackedCount: 10
        )
        let movieOpts = opts(releaseDate: isoDaysAgo(50.0), mediaKind: "movie")

        let ts = baseParsed(source: .ts)
        let tsResult = Scoring.scoreStream(parsed: ts, opts: movieOpts, corpus: corpus)
        XCTAssertEqual(tsResult.score, 35.0) // 20 (1080p) − 60 (telesync) + 75 (cinema window)
        XCTAssertEqual(
            tsResult.reasons.first { $0.signal == "fresh-theater-cinema-window" }?.delta, 75.0
        )

        let fakeWeb = baseParsed(resolution: .uhd, source: .webRip)
        let webResult = Scoring.scoreStream(parsed: fakeWeb, opts: movieOpts, corpus: corpus)
        XCTAssertEqual(webResult.score, -20.0) // 25 (4K) − 45 (fresh-fake-soft)
        XCTAssertEqual(webResult.reasons.first { $0.signal == "fresh-fake-soft" }?.delta, -45.0)
    }

    /// scoring.rs:1413 — non-dominated pool past 30 days: fresh heuristic is a no-op.
    func testFreshNonDominatedSkipsAfter30Days() {
        let corpus = CorpusStats(
            daysSinceRelease: 50.0,
            trustedTrackedFraction: 0.0,
            theaterCaptureFraction: 0.1,
            webishFraction: 0.7,
            trustedTrackedCount: 10
        )
        let movieOpts = opts(releaseDate: isoDaysAgo(50.0), mediaKind: "movie")
        let web = baseParsed(resolution: .uhd, source: .webRip)

        let result = Scoring.scoreStream(parsed: web, opts: movieOpts, corpus: corpus)
        XCTAssertEqual(result.score, 25.0)
        XCTAssertFalse(signals(result).contains { $0.hasPrefix("fresh-") })
    }

    // MARK: - Ranking (rank_and_pick) vectors

    /// scoring.rs:1604 — cached 4K (90) beats uncached 1080p (30) and cached 720p (50).
    func testRankPicksCachedTopTier() {
        let p1080 = baseParsed()
        var p4k = baseParsed(resolution: .uhd)
        p4k.cached["rd"] = true
        var p720 = baseParsed(resolution: .p720)
        p720.cached["rd"] = true

        let s1080 = scored(p1080, score: 30.0, tier: .p1080)
        let s4k = scored(p4k, score: 90.0, tier: .uhd)
        let s720 = scored(p720, score: 50.0, tier: .p720)

        let picker = Ranking.rankAndPick(scored: [s1080, s4k, s720], opts: opts(activeDebrids: ["rd"]))

        XCTAssertEqual(picker.primary?.tier, .uhd)
        XCTAssertEqual(picker.primary?.score, 90.0)

        // byTier holds the first stream per tier; Swift dictionaries are unordered,
        // so compare sorted keys (Rust's BTreeMap ordering is a serialization detail).
        XCTAssertEqual(picker.byTier.keys.sorted(), ["1080p", "4K", "720p"])
        XCTAssertEqual(picker.byTier["4K"]?.score, 90.0)
        XCTAssertEqual(picker.byTier["1080p"]?.score, 30.0)
        XCTAssertEqual(picker.byTier["720p"]?.score, 50.0)

        XCTAssertEqual(picker.all.count, 3)
        // all[0] must be cached (stable cached-first sort).
        XCTAssertTrue(picker.all[0].parsed.stream.url != nil || picker.all[0].parsed.cached["rd"] == true)
    }

    /// scoring.rs:1648 — no cached stream: Rust does NOT pre-sort by score, so the input
    /// order survives and 1080p (30) beats 4K (40).
    func testRankNoCachedKeepsInputOrderOverScore() {
        let s1080 = scored(baseParsed(), score: 30.0, tier: .p1080)
        let s4k = scored(baseParsed(resolution: .uhd), score: 40.0, tier: .uhd)

        let picker = Ranking.rankAndPick(scored: [s1080, s4k], opts: opts(activeDebrids: ["rd"]))

        XCTAssertEqual(picker.primary?.tier, .p1080)
        XCTAssertEqual(picker.all[0].tier, .p1080)
    }

    /// scoring.rs:1672 — respectAddonOrder: priority 0 / returnIdx 0 (score 30) ranks above
    /// priority 0 / returnIdx 1 (score 40), regardless of input order.
    func testRankRespectAddonOrderPreservesReturnIndexOverScore() {
        var p1080 = baseParsed()
        p1080.stream.addonPriority = 0
        p1080.stream.addonReturnIdx = 0
        p1080.stream.url = "http://a/1080"
        let s1080 = scored(p1080, score: 30.0, tier: .p1080)

        var p4k = baseParsed(resolution: .uhd)
        p4k.stream.addonPriority = 0
        p4k.stream.addonReturnIdx = 1
        p4k.stream.url = "http://a/4k"
        let s4k = scored(p4k, score: 40.0, tier: .uhd)

        let picker = Ranking.rankAndPick(scored: [s4k, s1080], opts: opts(respectAddonOrder: true))

        XCTAssertEqual(picker.all[0].tier, .p1080)
        XCTAssertEqual(picker.primary?.tier, .p1080)
    }

    /// scoring.rs:1706 — CAM-only pool: primary falls back to the non-theater 1080p stream.
    func testRankSkipsTheaterSourcesForPrimary() {
        let cam = scored(baseParsed(source: .cam), score: 0.0, tier: .rough)
        let p1080 = scored(baseParsed(), score: 0.0, tier: .p1080)

        let picker = Ranking.rankAndPick(scored: [cam, p1080], opts: opts())

        XCTAssertEqual(picker.primary?.tier, .p1080)
    }

    /// scoring.rs:1843 — higher-scored cached wins regardless of input order (80 vs 92 → 92).
    func testRankPrefersHigherScoredCachedRegardlessOfInputOrder() {
        var backup = baseParsed()
        backup.cached["rd"] = true
        backup.stream.addonPriority = 4
        let sBackup = scored(backup, score: 80.0, tier: .p1080)

        var top = baseParsed()
        top.cached["rd"] = true
        top.stream.addonPriority = 0
        let sTop = scored(top, score: 92.0, tier: .p1080)

        let picker = Ranking.rankAndPick(scored: [sBackup, sTop], opts: opts(activeDebrids: ["rd"]))

        XCTAssertEqual(picker.primary?.score, 92.0)
        XCTAssertEqual(picker.primary?.parsed.stream.addonPriority, 0)
    }

    // MARK: - Corpus statistics

    /// scoring.rs:1730 — [CAM cached-rd, WebDl 100 seeders, HDTV 5 seeders, BluRay url] →
    /// tracked 3, fraction 0.75, theater 1/3, webish 2/3.
    func testCorpusStatsBasicFractions() {
        var cam = baseParsed(source: .cam)
        cam.cached["rd"] = true
        var webDl = baseParsed()
        webDl.seeders = 100
        var hdtv = baseParsed(source: .hdtv)
        hdtv.seeders = 5
        var bluRay = baseParsed(source: .bluRay)
        bluRay.stream.url = "https://example.com/x"

        let stats = Scoring.computeCorpusStats(
            streams: [cam, webDl, hdtv, bluRay],
            opts: opts(activeDebrids: ["rd"])
        )

        XCTAssertEqual(stats.trustedTrackedCount, 3)
        XCTAssertEqual(stats.trustedTrackedFraction, 0.75, accuracy: 1e-9)
        XCTAssertEqual(stats.theaterCaptureFraction, 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(stats.webishFraction, 2.0 / 3.0, accuracy: 1e-9)
    }

    /// scoring.rs:1756 — empty corpus avoids divide-by-zero.
    func testCorpusStatsEmpty() {
        let stats = Scoring.computeCorpusStats(streams: [], opts: opts())

        XCTAssertEqual(stats.trustedTrackedCount, 0)
        XCTAssertEqual(stats.trustedTrackedFraction, 0.0)
        XCTAssertEqual(stats.theaterCaptureFraction, 0.0)
        XCTAssertEqual(stats.webishFraction, 0.0)
        XCTAssertNil(stats.daysSinceRelease)
    }

    // MARK: - Additional edge vectors

    /// scoring.rs:949-981 — year off-by-1 recent → −75; old mismatch → −70; old off-by-1 → −18.
    func testYearMismatchPenalties() {
        let recentDate = isoDaysAgo(100.0) // always within 365 days → "recent"
        let expectedRecentYear = Int(recentDate.prefix(4))!
        var offByOneRecent = baseParsed()
        offByOneRecent.year = expectedRecentYear - 1
        let recentOpts = opts(releaseDate: recentDate)
        XCTAssertEqual(
            Scoring.scoreStream(parsed: offByOneRecent, opts: recentOpts, corpus: emptyCorpus()).score,
            -55.0 // 20 − 75
        )

        var mismatchOld = baseParsed()
        mismatchOld.year = 2012
        let oldOpts = opts(releaseDate: "2010-05-01")
        let mismatchResult = Scoring.scoreStream(parsed: mismatchOld, opts: oldOpts, corpus: emptyCorpus())
        XCTAssertEqual(mismatchResult.score, -50.0) // 20 − 70
        XCTAssertTrue(signals(mismatchResult).contains("year-mismatch:2012vs2010"))

        var offByOneOld = baseParsed()
        offByOneOld.year = 2011
        let offByOneResult = Scoring.scoreStream(parsed: offByOneOld, opts: oldOpts, corpus: emptyCorpus())
        XCTAssertEqual(offByOneResult.score, 2.0) // 20 − 18
        XCTAssertTrue(signals(offByOneResult).contains("year-off-by-1:2011vs2010"))
    }

    /// scoring.rs:371-391 — mkv+DTS → −9; avi → −8; AV1 codec → −2 (after +1 codec boost).
    func testPlayabilityPenalty() {
        var mkvDts = baseParsed(audioCodec: .dts)
        mkvDts.container = .mkv
        let dtsResult = Scoring.scoreStream(parsed: mkvDts, opts: opts(), corpus: emptyCorpus())
        XCTAssertEqual(dtsResult.score, 11.0) // 20 − 6 − 3
        XCTAssertEqual(dtsResult.reasons.first { $0.signal == "webview2-unfriendly" }?.delta, -9.0)

        var avi = baseParsed()
        avi.container = .avi
        let aviResult = Scoring.scoreStream(parsed: avi, opts: opts(), corpus: emptyCorpus())
        XCTAssertEqual(aviResult.score, 12.0) // 20 − 8
        XCTAssertEqual(aviResult.reasons.first { $0.signal == "webview2-unfriendly" }?.delta, -8.0)

        let av1 = baseParsed(codec: .av1)
        let av1Result = Scoring.scoreStream(parsed: av1, opts: opts(), corpus: emptyCorpus())
        XCTAssertEqual(av1Result.score, 19.0) // 20 + 1 − 2
        XCTAssertEqual(av1Result.reasons.first { $0.signal == "webview2-unfriendly" }?.delta, -2.0)
    }

    /// scoring.rs:471-501 — size < 25% of runtime-derived minimum → −120; YTS exempt.
    func testSizeMismatchAndLossyGroupExemption() {
        let movieOpts = opts(runtimeMinutes: 100) // 1080p expected = 18 MiB/min × 100 ≈ 1.76 GiB

        var tiny = baseParsed()
        tiny.size = 100 * 1024 * 1024 // 100 MiB → ratio ≈ 0.055
        let tinyResult = Scoring.scoreStream(parsed: tiny, opts: movieOpts, corpus: emptyCorpus())
        XCTAssertEqual(tinyResult.score, -100.0) // 20 − 120
        XCTAssertEqual(tinyResult.reasons.first { $0.signal == "size-mismatch" }?.delta, -120.0)

        var yts = baseParsed()
        yts.size = 100 * 1024 * 1024
        yts.releaseGroupNormalized = "YTS"
        let ytsResult = Scoring.scoreStream(parsed: yts, opts: movieOpts, corpus: emptyCorpus())
        XCTAssertEqual(ytsResult.score, 20.0)
        XCTAssertNil(ytsResult.reasons.first { $0.signal == "size-mismatch" })
    }

    /// scoring.rs:503-573 — movie, 45 days old, non-theater, 4K at 1 GiB → −250
    /// (fresh heuristic skips: not dominated and days ≥ 30).
    func testUndersized4KNewRelease() {
        var parsed = baseParsed(resolution: .uhd)
        parsed.size = 1 * 1024 * 1024 * 1024 // 1 GiB
        let movieOpts = opts(releaseDate: isoDaysAgo(45.0), mediaKind: "movie")

        let result = Scoring.scoreStream(parsed: parsed, opts: movieOpts, corpus: emptyCorpus())
        XCTAssertEqual(result.score, -225.0) // 25 − 250
        XCTAssertEqual(result.reasons.first { $0.signal == "4k-undersized-1.0gb" }?.delta, -250.0)
    }

    /// scoring.rs:635-701 — movie, 10 days old, 480p at 100 MiB → new-release-virus −250
    /// (480p is outside the undersized-resolution checks; fresh adds −10).
    func testNewReleaseVirusTinyFile() {
        var parsed = baseParsed(resolution: .p480)
        parsed.size = 100 * 1024 * 1024 // 100 MiB < 250 MiB
        let movieOpts = opts(releaseDate: isoDaysAgo(10.0), mediaKind: "movie")

        let result = Scoring.scoreStream(parsed: parsed, opts: movieOpts, corpus: emptyCorpus())
        XCTAssertEqual(result.score, -258.0) // 2 (480p) − 250 (virus) − 10 (fresh-soft-flag)
        XCTAssertEqual(result.reasons.first { $0.signal == "new-release-virus-100mb" }?.delta, -250.0)
    }

    /// scoring.rs:580-633 — low-bandwidth: 4K under 25 Mbps −60/−30; 1080p under 8 Mbps −45/−20.
    func testLowBandwidthBitrateBudget() {
        let b10 = opts(bandwidthMbps: 10.0)

        let uncached4k = baseParsed(resolution: .uhd)
        XCTAssertEqual(
            Scoring.scoreStream(parsed: uncached4k, opts: b10, corpus: emptyCorpus()).score,
            -35.0 // 25 − 60
        )
        var cached4k = baseParsed(resolution: .uhd)
        cached4k.cached["rd"] = true
        let cachedOpts = opts(activeDebrids: ["rd"], bandwidthMbps: 10.0)
        XCTAssertEqual(
            Scoring.scoreStream(parsed: cached4k, opts: cachedOpts, corpus: emptyCorpus()).score,
            55.0 // 60 + 25 − 30
        )
        XCTAssertEqual(
            Scoring.scoreStream(parsed: cached4k, opts: cachedOpts, corpus: emptyCorpus())
                .reasons.first { $0.signal == "low-bandwidth-4k" }?.delta,
            -30.0
        )

        let b5 = opts(bandwidthMbps: 5.0)
        let p1080 = baseParsed()
        XCTAssertEqual(
            Scoring.scoreStream(parsed: p1080, opts: b5, corpus: emptyCorpus()).score,
            -25.0 // 20 − 45
        )
        var cached1080 = baseParsed()
        cached1080.cached["rd"] = true
        let cached5 = opts(activeDebrids: ["rd"], bandwidthMbps: 5.0)
        XCTAssertEqual(
            Scoring.scoreStream(parsed: cached1080, opts: cached5, corpus: emptyCorpus()).score,
            60.0 // 60 + 20 − 20
        )
    }

    /// scoring.rs:1063-1126 — Multi + preferSingleAudioTrack: −12 with no preferred list,
    /// −18 when preferred languages are set.
    func testMultiAudioTrackPenalties() {
        var multi = baseParsed()
        multi.audioLanguages = ["Multi"]

        let singleOnly = opts(preferSingleAudioTrack: true)
        XCTAssertEqual(
            Scoring.scoreStream(parsed: multi, opts: singleOnly, corpus: emptyCorpus()).score,
            8.0 // 20 − 12
        )

        let singlePreferred = opts(preferredLanguages: ["en"], preferSingleAudioTrack: true)
        let result = Scoring.scoreStream(parsed: multi, opts: singlePreferred, corpus: emptyCorpus())
        XCTAssertEqual(result.score, 2.0) // 20 − 18
        XCTAssertEqual(
            result.reasons.first { $0.signal == "html5-multi-audio-penalty" }?.delta, -18.0
        )
    }

    /// scoring.rs:1137-1143 + 844-866 — non-cached url earns "direct url" +25 and
    /// "prelinked-url" +4; a cached stream earns neither.
    func testDirectURLAndPrelinkedBoost() {
        var direct = baseParsed()
        direct.stream.url = "https://example.com/file.mkv"
        let result = Scoring.scoreStream(parsed: direct, opts: opts(), corpus: emptyCorpus())
        XCTAssertEqual(result.score, 49.0) // 20 + 25 + 4
        XCTAssertTrue(signals(result).contains("direct url"))
        XCTAssertTrue(signals(result).contains("prelinked-url"))
    }

    /// scoring.rs:1145-1153 — preferAddonId match earns the dominant +250 origin-addon signal.
    func testOriginAddonDominantSignal() {
        let parsed = baseParsed(addonId: "com.mediafusion")
        let result = Scoring.scoreStream(
            parsed: parsed,
            opts: opts(preferAddonId: "com.mediafusion"),
            corpus: emptyCorpus()
        )
        XCTAssertEqual(result.score, 270.0) // 20 + 250
        XCTAssertEqual(result.reasons.first { $0.signal == "origin-addon" }?.delta, 250.0)
    }

    /// scoring.rs:1128-1135 — scam score subtracts 1:1.
    func testScamPenalty() {
        var parsed = baseParsed()
        parsed.scamScore = 3
        let result = Scoring.scoreStream(parsed: parsed, opts: opts(), corpus: emptyCorpus())
        XCTAssertEqual(result.score, 17.0) // 20 − 3
        XCTAssertEqual(result.reasons.first { $0.signal == "scam-penalty" }?.delta, -3.0)
    }
}
