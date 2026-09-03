import XCTest
@testable import HarborIOS

// MARK: - TrustGate unit tests.
// Mirrors the 26 Rust trust tests (rust/harbor-core/src/trust.rs:662-1020,
// documented in docs/audit/stream-engine.md §7.1) plus additional pins for the
// exact floor bytes (audit §3.3), window edges, and the two documented
// divergences (D-TRUST-01 nzb, and Rust rule 13 applying to anime movies).

final class TrustGateTests: XCTestCase {

    private let mib: UInt64 = 1024 * 1024
    private let gib: UInt64 = 1024 * 1024 * 1024

    // MARK: - Fixture helpers (mirror Rust tests' base_stream / opts_strict)

    private func baseStream() -> ParsedStream {
        var s = ParsedStream()
        s.stream.infoHash = String(repeating: "a", count: 40)
        s.parsedTitle = "Sample Movie"
        s.resolution = .p1080
        s.codec = .hevc
        s.source = .webDl
        s.size = 2 * gib
        s.seeders = 50
        s.container = .mkv
        s.year = 2020
        return s
    }

    private func strictOpts() -> TrustOptions {
        TrustOptions(strict: true)
    }

    /// ISO-8601 date exactly `days` days ago (same civil-date math as the Rust
    /// tests use to build cinema-window fixtures).
    private func isoDaysAgo(_ days: Int64) -> String {
        let d = TrustGate.nowUnixMs() / 86_400_000 - days
        let c = TrustGate.civilFromDays(d)
        return String(format: "%04d-%02d-%02d", Int(c.year), c.month, c.day)
    }

    private func assertRejects(
        _ streams: [ParsedStream],
        opts: TrustOptions,
        reason expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = TrustGate.applyTrust(streams: streams, opts: opts)
        XCTAssertTrue(result.kept.isEmpty, "expected rejection \(expected)", file: file, line: line)
        XCTAssertEqual(result.rejected.count, 1, file: file, line: line)
        XCTAssertEqual(result.rejected.first?.reason, expected, file: file, line: line)
    }

    private func assertKeeps(
        _ streams: [ParsedStream],
        opts: TrustOptions,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = TrustGate.applyTrust(streams: streams, opts: opts)
        XCTAssertEqual(result.kept.count, streams.count, file: file, line: line)
        XCTAssertTrue(result.rejected.isEmpty, "unexpected: \(result.rejected.map(\.reason))",
                      file: file, line: line)
    }

    // MARK: - Rust test mirrors (audit §7.1 trust list)

    func testKeepsCleanStream() {
        assertKeeps([baseStream()], opts: strictOpts())
    }

    func testDisabledShortCircuits() {
        var opts = strictOpts()
        opts.disabled = true
        opts.expectedYear = 1900
        var bad = baseStream()
        bad.size = 500 * gib
        assertKeeps([baseStream(), bad], opts: opts)
    }

    func testRejectsSuspiciousExtension() {
        var s = baseStream()
        s.stream.behaviorHints = EngineBehaviorHints(filename: "Setup.exe")
        assertRejects([s], opts: strictOpts(), reason: "suspicious-extension:.exe")
    }

    func testSuspiciousExtensionBeatsTrailerRule() {
        // Rule 4 precedes rule 5 — .exe wins even though "trailer" is present.
        var s = baseStream()
        s.stream.behaviorHints = EngineBehaviorHints(filename: "movie.trailer.exe")
        assertRejects([s], opts: strictOpts(), reason: "suspicious-extension:.exe")
    }

    func testRejectsTrailerBelowCeiling() {
        var s = baseStream()
        s.stream.behaviorHints = EngineBehaviorHints(filename: "movie.trailer.mkv")
        s.size = 50 * mib
        assertRejects([s], opts: strictOpts(), reason: "trailer-or-extra")
    }

    func testTrailerBeatsSizeStub() {
        // Rule 5 precedes rule 7 — trailer wins over the tiny size.
        var s = baseStream()
        s.stream.behaviorHints = EngineBehaviorHints(filename: "movie.trailer.mkv")
        s.size = 1 * mib
        assertRejects([s], opts: strictOpts(), reason: "trailer-or-extra")
    }

    func testRejectsUnderscoreDelimitedTrailer() {
        var s = baseStream()
        s.stream.behaviorHints = EngineBehaviorHints(filename: "Movie_2025_trailer_1080p.mkv")
        assertRejects([s], opts: strictOpts(), reason: "trailer-or-extra")
    }

    func testRejectsNoPlayableSource() {
        var s = baseStream()
        s.stream.infoHash = nil
        assertRejects([s], opts: strictOpts(), reason: "no-playable-source")
    }

    func testNZBOnlyStreamDivergenceFromRust() {
        // DIVERGENCE D-TRUST-01: Rust keeps an nzb-only stream (trust.rs test
        // `keeps_nzb_only_stream`, extra["nzbUrl"]). The canonical Swift
        // EngineStream has no `extra` bag / nzbUrl field, so the trust layer
        // cannot see it and rejects as no-playable-source. NZB playback is owned
        // by the resolve layer (StremioStream.nzbUrl). Update this test if the
        // contract ever gains an extra bag.
        var s = baseStream()
        s.stream.infoHash = nil
        assertRejects([s], opts: strictOpts(), reason: "no-playable-source")
    }

    func testRejectsSizeStub() {
        var s = baseStream()
        s.size = 1 * mib
        assertRejects([s], opts: strictOpts(), reason: "size-stub")
    }

    func testSizeStubBoundaryIsStrict() {
        // size == 5 MiB passes rule 7; 4 MiB + 1 MiB - 1 byte still rejects.
        var s = baseStream()
        s.size = 5 * mib
        assertKeeps([s], opts: strictOpts())
        s.size = 5 * mib - 1
        assertRejects([s], opts: strictOpts(), reason: "size-stub")
    }

    func testRejectsScamScore7() {
        var s = baseStream()
        s.scamScore = 7
        assertRejects([s], opts: strictOpts(), reason: "scam-score-7")
    }

    func testScamScoreGateBoundary() {
        var s = baseStream()
        s.scamScore = 4
        assertKeeps([s], opts: strictOpts())
        s.scamScore = 5
        assertRejects([s], opts: strictOpts(), reason: "scam-score-5")
    }

    func testScamScoreExemptWithAllowCam() {
        var s = baseStream()
        s.scamScore = 7
        var opts = strictOpts()
        opts.allowCam = true
        assertKeeps([s], opts: opts)
    }

    func testScamScoreExemptOlderCatalogByYearGap() {
        var s = baseStream()
        s.scamScore = 7
        var opts = strictOpts()
        opts.expectedYear = TrustGate.currentYear() - 5   // gap > 2 → older catalog
        assertKeeps([s], opts: opts)
    }

    func testRejectsSeriesResultForMovieEpisodeShape() {
        var s = baseStream()
        s.parsedTitle = "Obsession"
        s.season = 1
        s.episode = 1
        var opts = strictOpts()
        opts.kind = "movie"
        assertRejects([s], opts: opts, reason: "series-result-for-movie")
    }

    func testRejectsSeriesResultForMovieSeasonPackShape() {
        var s = baseStream()
        s.parsedTitle = "Obsession"
        s.seasonPack = true
        s.season = 1
        var opts = strictOpts()
        opts.kind = "movie"
        assertRejects([s], opts: opts, reason: "series-result-for-movie")
    }

    func testAnimeSkipsSeriesResultForMovie() {
        var s = baseStream()
        s.parsedTitle = "Obsession"
        s.season = 1
        s.episode = 1
        var opts = strictOpts()
        opts.kind = "movie"
        opts.isAnime = true
        assertKeeps([s], opts: opts)
    }

    func testRejectsCinemaBareUntagged() {
        var s = baseStream()
        s.parsedTitle = "Obsession"
        s.year = nil
        s.source = .other
        s.resolution = .sd
        var opts = strictOpts()
        opts.kind = "movie"
        opts.expectedYear = 2025
        opts.releaseDate = isoDaysAgo(7)
        assertRejects([s], opts: opts, reason: "cinema-bare-untagged")
    }

    func testKeepsRealMovieInCinemaWindow() {
        var s = baseStream()
        s.parsedTitle = "Obsession"
        s.year = 2025
        s.source = .webDl
        s.resolution = .p1080
        var opts = strictOpts()
        opts.kind = "movie"
        opts.expectedYear = 2025
        opts.releaseDate = isoDaysAgo(7)
        assertKeeps([s], opts: opts)
    }

    func testRejectsCinemaYearMismatch() {
        var s = baseStream()
        s.parsedTitle = "The Strangers"
        s.year = 2008
        s.resolution = .p720
        s.source = .webDl
        var opts = strictOpts()
        opts.kind = "movie"
        opts.expectedYear = 2025
        opts.releaseDate = isoDaysAgo(7)
        assertRejects([s], opts: opts, reason: "cinema-year-mismatch:2008-vs-2025")
    }

    func testRejectsFreshCinemaFakeHDTV() {
        var s = baseStream()
        s.parsedTitle = "New Movie"
        s.year = 2025
        s.source = .hdtv
        s.resolution = .p1080
        var opts = strictOpts()
        opts.kind = "movie"
        opts.expectedYear = 2025
        opts.releaseDate = isoDaysAgo(7)
        assertRejects([s], opts: opts, reason: "fresh-cinema-fake-hdtv")
    }

    func testRejectsFreshCinemaFakeBluray() {
        var s = baseStream()
        s.parsedTitle = "New Movie"
        s.year = 2025
        s.source = .bluRay
        s.resolution = .p1080
        var opts = strictOpts()
        opts.kind = "movie"
        opts.expectedYear = 2025
        opts.releaseDate = isoDaysAgo(7)
        assertRejects([s], opts: opts, reason: "fresh-cinema-fake-bluray")
    }

    func testRejectsFreshCinemaFakeBlurayViaRemuxFlag() {
        var s = baseStream()
        s.parsedTitle = "New Movie"
        s.year = 2025
        s.source = .webDl   // not BluRay, but the remux flag alone triggers rule 16
        s.remux = true
        s.size = 3 * gib
        var opts = strictOpts()
        opts.kind = "movie"
        opts.expectedYear = 2025
        opts.releaseDate = isoDaysAgo(7)
        assertRejects([s], opts: opts, reason: "fresh-cinema-fake-bluray")
    }

    func testRejectsFreshCinemaFake4KWeb() {
        var s = baseStream()
        s.parsedTitle = "New Movie"
        s.year = 2025
        s.source = .webDl
        s.resolution = .uhd
        s.size = 3 * gib   // ≥ 4K cinema floor (2560 MiB) so rule 17 is reached
        var opts = strictOpts()
        opts.kind = "movie"
        opts.expectedYear = 2025
        opts.releaseDate = isoDaysAgo(7)
        assertRejects([s], opts: opts, reason: "fresh-cinema-fake-4k-web")
    }

    func testEpisodeStubRejectedNonAnimeKeptAnime() {
        var s = baseStream()
        s.resolution = .p1080
        s.size = 180 * mib
        var opts = strictOpts()
        opts.kind = "series"
        assertRejects([s], opts: opts, reason: "episode-stub-too-small-for-1080p")
        opts.isAnime = true
        assertKeeps([s], opts: opts)
    }

    func testShortFormatExemptsSmallEpisode() {
        var s = baseStream()
        s.stream.behaviorHints = EngineBehaviorHints(filename: "Show.OVA.1080p.mkv")
        s.resolution = .p1080
        s.size = 80 * mib
        var opts = strictOpts()
        opts.kind = "series"
        assertKeeps([s], opts: opts)
    }

    func testTitleShortGuardRejectsKeywordInLongTitle() {
        var s = baseStream()
        s.parsedTitle = "DBM Obsession Viva Las Vegas"
        s.year = 2025
        var opts = strictOpts()
        opts.kind = "movie"
        opts.expectedTitle = "Obsession"
        opts.expectedYear = 2025
        assertRejects([s], opts: opts, reason: "title-mismatch")
    }

    func testTitleYearToleranceScalesWithAge() {
        // Rust test title_year_tolerance_scales_with_age: expected "Rocky" (1976),
        // parsed "Rocky II" (1979): sequel present on parsed side only, year
        // distance 3 ≤ tolerance 4 (age 50 ≥ 30) → true.
        XCTAssertTrue(TrustGate.titleMatches(
            expected: "Rocky", parsed: "Rocky II", parsedYear: 1979, expectedYear: 1976))
        // Same pair, young catalog: tolerance 1, distance 3 → false.
        XCTAssertFalse(TrustGate.titleMatches(
            expected: "Rocky", parsed: "Rocky II", parsedYear: 1979,
            expectedYear: TrustGate.currentYear() - 3))
    }

    func testTitleMatchesSequelRules() {
        // Both sequel markers present and equal → pass regardless of year.
        XCTAssertTrue(TrustGate.titleMatches(
            expected: "Rocky II", parsed: "Rocky 2", parsedYear: 1979, expectedYear: 1979))
        // Both present and different → fail.
        XCTAssertFalse(TrustGate.titleMatches(
            expected: "Rocky II", parsed: "Rocky III", parsedYear: 1979, expectedYear: 1979))
        // Expected sequel, parsed without one, year distance beyond tolerance → fail.
        XCTAssertFalse(TrustGate.titleMatches(
            expected: "Rocky II", parsed: "Rocky", parsedYear: 2015,
            expectedYear: TrustGate.currentYear() - 3))
    }

    func testSequelMarker() {
        XCTAssertEqual(TrustGate.sequelMarker("Rocky II"), 2)
        XCTAssertEqual(TrustGate.sequelMarker("Rocky IV"), 4)
        XCTAssertEqual(TrustGate.sequelMarker("Rocky 2"), 2)
        XCTAssertEqual(TrustGate.sequelMarker("Rocky (1976) II"), 2)
        XCTAssertEqual(TrustGate.sequelMarker("Mission: Impossible III"), 3)
        XCTAssertNil(TrustGate.sequelMarker("Rocky"))
        XCTAssertNil(TrustGate.sequelMarker("Rocky I"))       // roman "i" is not in the map
        XCTAssertNil(TrustGate.sequelMarker("Rocky XI"))      // beyond the ii..x map
        XCTAssertNil(TrustGate.sequelMarker("Rocky 21"))      // digits beyond 20
        XCTAssertNil(TrustGate.sequelMarker("Part One"))      // part-word stripped, no tail token
        XCTAssertNil(TrustGate.sequelMarker("Rocky 2024"))    // 4-digit year is not a sequel tail
    }

    func testTokenizeDecomposesPrecomposedAccents() {
        // Rust test tokenize_decomposes_precomposed_accents.
        XCTAssertEqual(TrustGate.tokenize("Amélie"), ["amelie"])
        XCTAssertEqual(TrustGate.tokenize("Pokémon"), ["pokemon"])
        XCTAssertEqual(TrustGate.tokenize("The Matrix 1999"), ["matrix", "1999"])
        XCTAssertEqual(TrustGate.tokenize("Aliens vs. Predator"), ["aliens", "predator"])
    }

    func testSeasonPackWithFileIdxSkipsEpisodeCheck() {
        var s = baseStream()
        s.stream.fileIdx = 2
        s.episode = 7
        var opts = strictOpts()
        opts.expectedEpisode = 3
        assertKeeps([s], opts: opts)
    }

    func testSeasonPackSkipsSeasonAndEpisodeGates() {
        // Rust test allows_season_pack_when_flag_set. NOTE: opts.allowSeasonPacks
        // is dead in the Rust trust gate — the exemption is the stream's own
        // seasonPack flag (trust.rs:374-392).
        var s = baseStream()
        s.seasonPack = true
        s.season = 2   // deliberately ≠ expectedSeason
        var opts = strictOpts()
        opts.allowSeasonPacks = true
        opts.expectedSeason = 1
        opts.expectedEpisode = 3
        assertKeeps([s], opts: opts)
    }

    func testRejectsSeasonMismatch() {
        var s = baseStream()
        s.season = 2
        var opts = strictOpts()
        opts.kind = "series"
        opts.expectedSeason = 1
        assertRejects([s], opts: opts, reason: "season-mismatch:2-vs-1")
    }

    func testRejectsEpisodeMismatch() {
        var s = baseStream()
        s.episode = 5
        var opts = strictOpts()
        opts.kind = "series"
        opts.expectedEpisode = 3
        assertRejects([s], opts: opts, reason: "episode-mismatch:5-vs-3")
    }

    func testAnimeSkipsSeasonEpisodeGates() {
        var s = baseStream()
        s.season = 2
        s.episode = 5
        var opts = strictOpts()
        opts.kind = "series"
        opts.isAnime = true
        opts.expectedSeason = 1
        opts.expectedEpisode = 3
        assertKeeps([s], opts: opts)
    }

    func testRejectsPlaceholderBanner() {
        for description in ["🚫 No streams found", "⚠️ Streams filtered", "ℹ️ no streams available"] {
            var s = baseStream()
            s.stream.description = description
            assertRejects([s], opts: strictOpts(), reason: "addon-placeholder-banner")
        }
    }

    func testRejectsStatusCard() {
        var s = baseStream()
        s.stream.infoHash = nil
        s.stream.url = "https://example.com/account"
        s.stream.description = "Premium expires in 3 days"
        assertRejects([s], opts: strictOpts(), reason: "addon-status-card")
    }

    func testStatusCardCamelCaseFilenameNotExempted() {
        // Rust test status_card_camelcase_filename_not_exempted: only the
        // snake_case `filename` hint exempts the status card, never `fileName`.
        var s = baseStream()
        s.stream.infoHash = nil
        s.stream.url = "https://example.com/acct"
        s.stream.description = "Premium expires in 3 days"
        s.stream.behaviorHints = EngineBehaviorHints(fileName: "card.mkv")
        assertRejects([s], opts: strictOpts(), reason: "addon-status-card")
    }

    func testStatusCardExemptedByFilenameOrVideoSizeOrVideoURL() {
        // snake_case filename exempts…
        var s = baseStream()
        s.stream.infoHash = nil
        s.stream.url = "https://example.com/acct"
        s.stream.description = "Premium expires in 3 days"
        s.stream.behaviorHints = EngineBehaviorHints(filename: "card.mkv")
        assertKeeps([s], opts: strictOpts())

        // …videoSize ≠ 0 exempts…
        s = baseStream()
        s.stream.infoHash = nil
        s.stream.url = "https://example.com/acct"
        s.stream.description = "Quota used 80%"
        s.stream.behaviorHints = EngineBehaviorHints(videoSize: 100)
        assertKeeps([s], opts: strictOpts())

        // …and a video-extension URL never enters the status-card branch.
        s = baseStream()
        s.stream.infoHash = nil
        s.stream.url = "https://cdn.example.com/movie.mkv"
        s.stream.description = "Premium expires in 3 days"
        assertKeeps([s], opts: strictOpts())
    }

    func testRejectsUncachedEmoji() {
        var s = baseStream()
        s.stream.name = "⏳ Cloud only"
        assertRejects([s], opts: strictOpts(), reason: "addon-uncached-emoji")
    }

    // MARK: - Rust-rule parity pins not covered by the Rust unit tests

    func testAnimeMovieStillTitleChecked() {
        // Parity note: the audit §5.1 summary claims rule 13 is skipped for anime,
        // but trust.rs:283-296 (and the audit's own §3.2 condition table) apply
        // title-mismatch to movies regardless of isAnime. This test pins the Rust
        // behavior; only rules 11, 12, 20, 21, 22 have the isAnime skip.
        var s = baseStream()
        s.parsedTitle = "The Emoji Movie"
        s.year = 2017
        var opts = strictOpts()
        opts.kind = "movie"
        opts.isAnime = true
        opts.expectedTitle = "The Lion King"
        opts.expectedYear = 1994
        assertRejects([s], opts: opts, reason: "title-mismatch")
    }

    func testSeriesTitleMismatchSkippedForAnime() {
        var s = baseStream()
        s.parsedTitle = "Better Call Saul"
        s.year = 2015
        var opts = strictOpts()
        opts.kind = "series"
        opts.expectedTitle = "Breaking Bad"
        opts.expectedYear = 2008
        assertRejects([s], opts: opts, reason: "title-mismatch")
        opts.isAnime = true
        assertKeeps([s], opts: opts)
    }

    func testRejectsFilenameMissingSequel() {
        var s = baseStream()
        s.parsedTitle = "Mission: Impossible III"
        s.stream.title = "Mission Impossible 2015"
        s.stream.behaviorHints = EngineBehaviorHints(filename: "Mission.Impossible.2015.1080p.mkv")
        var opts = strictOpts()
        opts.kind = "movie"
        opts.expectedTitle = "Mission: Impossible III"
        assertRejects([s], opts: opts, reason: "filename-missing-sequel")
    }

    func testKeepsFilenameWithSequelToken() {
        // digit / roman / word forms all satisfy the sequel-token check.
        for filename in [
            "Mission.Impossible.III.2015.1080p.mkv",
            "Mission.Impossible.3.2015.1080p.mkv",
            "Mission.Impossible.Three.2015.1080p.mkv",
        ] {
            var s = baseStream()
            s.parsedTitle = "Mission: Impossible III"
            s.stream.title = "Mission Impossible 2015"
            s.stream.behaviorHints = EngineBehaviorHints(filename: filename)
            var opts = strictOpts()
            opts.kind = "movie"
            opts.expectedTitle = "Mission: Impossible III"
            assertKeeps([s], opts: opts)
        }
    }

    func testNewReleaseVirus() {
        var s = baseStream()
        s.year = 2025
        s.resolution = .sd
        s.source = .webDl
        s.size = 210 * mib   // ≥ SD cinema floor (200 MiB), < 250 MiB virus cutoff
        var opts = strictOpts()
        opts.kind = "movie"
        opts.expectedYear = 2025
        opts.releaseDate = isoDaysAgo(7)
        assertRejects([s], opts: opts, reason: "new-release-virus-210mb")
    }

    func testNewReleaseStubAndShortFormatExemption() {
        var s = baseStream()
        s.year = 2025
        s.resolution = .sd
        s.source = .webDl
        s.size = 300 * mib   // ≥ 250 MiB virus cutoff, < 500 MiB stub cutoff
        var opts = strictOpts()
        opts.kind = "movie"
        opts.expectedYear = 2025
        opts.releaseDate = isoDaysAgo(7)
        assertRejects([s], opts: opts, reason: "new-release-stub-300mb")

        // Short-format marker exempts rule 10.
        var short = s
        short.stream.behaviorHints = EngineBehaviorHints(filename: "Movie.Short.1080p.mkv")
        assertKeeps([short], opts: opts)
    }

    func testTheaterSourceSkipsVirusRules() {
        var s = baseStream()
        s.year = 2025
        s.resolution = .sd
        s.source = .cam
        s.size = 210 * mib
        var opts = strictOpts()
        opts.kind = "movie"
        opts.expectedYear = 2025
        opts.releaseDate = isoDaysAgo(7)
        assertKeeps([s], opts: opts)
    }

    func testMovieFloor1080pCinemaBoundary() {
        var s = baseStream()
        s.year = 2025
        s.resolution = .p1080
        s.source = .webDl
        var opts = strictOpts()
        opts.kind = "movie"
        opts.expectedYear = 2025
        opts.releaseDate = isoDaysAgo(7)

        s.size = 1_288_490_189 - 1
        assertRejects([s], opts: opts, reason: "movie-stub-too-small-for-1080p")
        s.size = 1_288_490_189   // exactly ⌈6 GiB / 5⌉ — strict < passes it
        assertKeeps([s], opts: opts)
    }

    func testEpisodeFloorWindowColumns() {
        var s = baseStream()
        s.resolution = .p1080
        s.size = 150 * mib   // ≥ older (100) and anime-normal (150), < cinema (400) & normal (250)
        var opts = strictOpts()
        opts.kind = "series"

        opts.releaseDate = isoDaysAgo(800)   // older catalog → floor 100 MiB
        assertKeeps([s], opts: opts)
        opts.releaseDate = isoDaysAgo(10)    // cinema window → floor 400 MiB
        assertRejects([s], opts: opts, reason: "episode-stub-too-small-for-1080p")
        opts.releaseDate = isoDaysAgo(200)   // normal → floor 250 MiB
        assertRejects([s], opts: opts, reason: "episode-stub-too-small-for-1080p")
    }

    // MARK: - Exact floor bytes (audit §3.3)

    func testSizeFloorExactBytes() {
        // Movie table.
        XCTAssertEqual(TrustGate.sizeFloor(kind: "movie", resolution: .uhd, window: .cinema, isAnime: false), 2_684_354_560)     // 2560 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "movie", resolution: .uhd, window: .normal, isAnime: false), 1_610_612_736)      // 1536 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "movie", resolution: .uhd, window: .older, isAnime: false), 629_145_600)         // 600 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "movie", resolution: .p1080, window: .cinema, isAnime: false), 1_288_490_189)    // ⌈6 GiB / 5⌉
        XCTAssertEqual(TrustGate.sizeFloor(kind: "movie", resolution: .p1080, window: .normal, isAnime: false), 734_003_200)      // 700 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "movie", resolution: .p1080, window: .older, isAnime: false), 262_144_000)       // 250 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "movie", resolution: .p720, window: .cinema, isAnime: false), 629_145_600)       // 600 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "movie", resolution: .p720, window: .normal, isAnime: false), 419_430_400)       // 400 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "movie", resolution: .p720, window: .older, isAnime: false), 125_829_120)        // 120 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "movie", resolution: .p480, window: .cinema, isAnime: false), 262_144_000)       // 250 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "movie", resolution: .p480, window: .normal, isAnime: false), 157_286_400)       // 150 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "movie", resolution: .p480, window: .older, isAnime: false), 52_428_800)         // 50 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "movie", resolution: .sd, window: .cinema, isAnime: false), 209_715_200)         // 200 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "movie", resolution: .sd, window: .normal, isAnime: false), 104_857_600)         // 100 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "movie", resolution: .sd, window: .older, isAnime: false), 26_214_400)           // 25 MiB

        // Episode table.
        XCTAssertEqual(TrustGate.sizeFloor(kind: "series", resolution: .uhd, window: .cinema, isAnime: false), 1_073_741_824)     // 1024 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "series", resolution: .uhd, window: .normal, isAnime: false), 629_145_600)       // 600 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "series", resolution: .uhd, window: .older, isAnime: false), 209_715_200)        // 200 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "series", resolution: .p1080, window: .cinema, isAnime: false), 419_430_400)     // 400 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "series", resolution: .p1080, window: .normal, isAnime: false), 262_144_000)     // 250 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "series", resolution: .p1080, window: .older, isAnime: false), 104_857_600)      // 100 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "series", resolution: .p720, window: .normal, isAnime: false), 125_829_120)      // 120 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "series", resolution: .p480, window: .normal, isAnime: false), 52_428_800)       // 50 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "series", resolution: .sd, window: .normal, isAnime: false), 31_457_280)         // 30 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "series", resolution: .sd, window: .older, isAnime: false), 8_388_608)           // 8 MiB

        // Anime episode table.
        XCTAssertEqual(TrustGate.sizeFloor(kind: "series", resolution: .uhd, window: .cinema, isAnime: true), 629_145_600)        // 600 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "series", resolution: .uhd, window: .normal, isAnime: true), 419_430_400)        // 400 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "series", resolution: .uhd, window: .older, isAnime: true), 157_286_400)         // 150 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "series", resolution: .p1080, window: .cinema, isAnime: true), 230_686_720)      // 220 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "series", resolution: .p1080, window: .normal, isAnime: true), 157_286_400)      // 150 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "series", resolution: .p1080, window: .older, isAnime: true), 52_428_800)        // 50 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "series", resolution: .p720, window: .normal, isAnime: true), 62_914_560)        // 60 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "series", resolution: .p480, window: .normal, isAnime: true), 29_360_128)        // 28 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "series", resolution: .sd, window: .normal, isAnime: true), 18_874_368)          // 18 MiB
        XCTAssertEqual(TrustGate.sizeFloor(kind: "series", resolution: .sd, window: .older, isAnime: true), 5_242_880)            // 5 MiB

        XCTAssertEqual(TrustGate.tinyStubFloor, 5_242_880)   // 5 MiB
    }

    // MARK: - Window / date helpers (trust.rs:587-660)

    func testCinemaWindowEdges() {
        // Window is -90 < days < 60: up to 59.99 days in the past, up to 89.99 in
        // the future. 60+ days ago is OUT.
        XCTAssertTrue(TrustGate.isInCinemaWindow(releaseDate: isoDaysAgo(59)))
        XCTAssertFalse(TrustGate.isInCinemaWindow(releaseDate: isoDaysAgo(61)))
        XCTAssertFalse(TrustGate.isInCinemaWindow(releaseDate: nil))
        XCTAssertFalse(TrustGate.isInCinemaWindow(releaseDate: "not-a-date"))

        // Future dates: inside the +60-day future bound. Harbor's window is
        // asymmetric: -90 < days_since_release < 60 → future releases are IN up
        // to ~90 days ahead (negative days_since_release); 91+ days ahead is OUT.
        let future30 = TrustGate.civilFromDays(TrustGate.nowUnixMs() / 86_400_000 + 30)
        XCTAssertTrue(TrustGate.isInCinemaWindow(
            releaseDate: String(format: "%04d-%02d-%02d", Int(future30.year), future30.month, future30.day)))
        let future91 = TrustGate.civilFromDays(TrustGate.nowUnixMs() / 86_400_000 + 91)
        XCTAssertFalse(TrustGate.isInCinemaWindow(
            releaseDate: String(format: "%04d-%02d-%02d", Int(future91.year), future91.month, future91.day)))
    }

    func testCinemaWindowDrivesFloorAndFreshRules() {
        var s = baseStream()
        s.year = 2025
        s.source = .bluRay
        s.resolution = .p1080
        s.size = 1 * gib   // < 1080p cinema floor (1288.49 MB), > normal floor (700 MiB)
        var opts = strictOpts()
        opts.kind = "movie"
        opts.expectedYear = 2025

        opts.releaseDate = isoDaysAgo(59)   // in window: cinema floor + fresh-bluray rule
        assertRejects([s], opts: opts, reason: "movie-stub-too-small-for-1080p")
        opts.releaseDate = isoDaysAgo(61)   // out of window: normal floor, no fresh rules
        assertKeeps([s], opts: opts)
    }

    func testOlderCatalogEdges() {
        XCTAssertTrue(TrustGate.isOlderCatalog(releaseDate: isoDaysAgo(800), expectedYear: nil))
        XCTAssertFalse(TrustGate.isOlderCatalog(releaseDate: isoDaysAgo(100), expectedYear: nil))
        XCTAssertTrue(TrustGate.isOlderCatalog(
            releaseDate: nil, expectedYear: TrustGate.currentYear() - 3))
        XCTAssertFalse(TrustGate.isOlderCatalog(
            releaseDate: nil, expectedYear: TrustGate.currentYear()))
        XCTAssertFalse(TrustGate.isOlderCatalog(releaseDate: nil, expectedYear: nil))
        // Unparseable release date falls through to the year-gap branch.
        XCTAssertTrue(TrustGate.isOlderCatalog(
            releaseDate: "not-a-date", expectedYear: TrustGate.currentYear() - 3))
        // Parseable release date short-circuits the year-gap branch.
        XCTAssertFalse(TrustGate.isOlderCatalog(
            releaseDate: isoDaysAgo(100), expectedYear: TrustGate.currentYear() - 3))
    }

    func testParseISODateQuirks() {
        // Cut at first 'T' or ' '; extra segments after day are ignored.
        XCTAssertEqual(TrustGate.parseISODateToUnixMs("2025-07-01T10:30:00Z"),
                       TrustGate.parseISODateToUnixMs("2025-07-01"))
        XCTAssertEqual(TrustGate.parseISODateToUnixMs("2025-07-01-extra"),
                       TrustGate.parseISODateToUnixMs("2025-07-01"))
        // Trimmed; unpadded month/day accepted.
        XCTAssertEqual(TrustGate.parseISODateToUnixMs(" 2025-07-01 "),
                       TrustGate.parseISODateToUnixMs("2025-07-01"))
        XCTAssertEqual(TrustGate.parseISODateToUnixMs("2025-1-5"),
                       TrustGate.parseISODateToUnixMs("2025-01-05"))
        // Rust validates only 1≤m≤12, 1≤d≤31 — 2025-02-31 parses.
        XCTAssertNotNil(TrustGate.parseISODateToUnixMs("2025-02-31"))
        // Invalid shapes.
        XCTAssertNil(TrustGate.parseISODateToUnixMs("2025-13-01"))
        XCTAssertNil(TrustGate.parseISODateToUnixMs("2025-07-00"))
        XCTAssertNil(TrustGate.parseISODateToUnixMs("2025-07"))
        XCTAssertNil(TrustGate.parseISODateToUnixMs("2025--07"))
        XCTAssertNil(TrustGate.parseISODateToUnixMs("garbage"))
        XCTAssertNil(TrustGate.parseISODateToUnixMs(""))
    }
}
