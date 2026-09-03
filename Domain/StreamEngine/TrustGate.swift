import Foundation

// MARK: - Trust gate
//
// Swift port of `rust/harbor-core/src/trust.rs` (which is itself the mirror of
// `src/lib/streams/trust.ts`). Canonical behavioral reference:
// `docs/audit/stream-engine.md` §3 (gate preconditions, the 23 rejection rules
// in exact first-match-wins order, the size-floor tables, and the title_matches
// algorithm). Parity follows RUST semantics wherever the audit flags TS≠RUST.
//
// Contract: types come verbatim from `EngineModels.swift` (do not modify).
//
// Documented divergences (see also docs/IOS_STREAM_ENGINE.md §9):
// - D-TRUST-01: Rust counts `stream.extra["nzbUrl"]` as a playable source
//   (trust.rs:171). The canonical Swift `EngineStream` has no `extra` bag and no
//   nzbUrl field, so NZB-only streams fall through to `no-playable-source`.
//   NZB handling at playback time lives in the resolve layer, keyed off the
//   addon-level model (`StremioStream.nzbUrl`), which is unaffected.

enum TrustGate {

    // MARK: - Constants (trust.rs:11-15, 60-62)

    static let kib: UInt64 = 1024
    static let mib: UInt64 = kib * 1024              // 1,048,576
    static let gib: UInt64 = mib * 1024              // 1,073,741,824

    /// trust.rs:15 — `TINY_STUB_FLOOR` = 5 MiB = 5,242,880 B.
    static let tinyStubFloor: UInt64 = 5 * mib

    /// trust.rs:60-62 — FILENAME_BLACKLIST, exact order (the first matching
    /// extension in iteration order wins the reason string).
    static let filenameBlacklist: [String] = [
        ".exe", ".zip", ".rar", ".lnk", ".scr", ".bat", ".iso", ".img",
    ]

    /// trust.rs:109-116 — TITLE_STOPWORDS (tokenize() drops these).
    static let titleStopwords: Set<String> = [
        "the", "a", "an", "of", "and", "in", "to", "for", "on", "at", "by", "is", "or", "as",
        "from", "with", "into", "movie", "film",
    ]

    /// ⌈6 GiB / 5⌉ = 1,288,490,189 B — the movie 1080p cinema floor
    /// (trust.rs:20 `(GIB * 6).div_ceil(5)`; audit §3.3 "1288.49" is the decimal-MB
    /// rendering of the same number; TS `Math.round(1.2 * GIB)` agrees).
    static let movie1080pCinemaFloor: UInt64 = (gib * 6 + 4) / 5

    // MARK: - Regexes (trust.rs:64-104)
    // `NSRegularExpression` is ICU-based; every pattern below is ported 1:1 from
    // the Rust `regex` crate sources. Emoji scalars are pinned by code point so the
    // variation-selector details survive exactly (e.g. `⚠️?` is U+26A0 + U+FE0F?).

    /// trust.rs:64-68 — SHORT_FORMAT_RX. Exempts rules 10 and 19.
    static let shortFormatRX = try! NSRegularExpression(
        pattern: #"\b(short|shorts|mini|mini[\s.\-_]?episode|ova|special|specials|skit|sketch|chibi|micro|webisode|vignette|interlude)\b"#, options: [.caseInsensitive])

    /// trust.rs:71 — UNCACHED_EMOJI_RX.
    static let uncachedEmojiRX = try! NSRegularExpression(
        pattern: "[\x{2B07}\x{23F3}\x{231B}\x{23EC}\x{1F53D}\x{1F4E5}\x{2601}]", options: [.caseInsensitive])

    /// trust.rs:73-78 — PLACEHOLDER_BANNER_RX.
    static let placeholderBannerRX = try! NSRegularExpression(
        pattern: #"(?:\x{1F6AB}|\x{26A0}\x{FE0F}?|\x{2757}|\x{2139}\x{FE0F}?)\s*(?:no\s+streams?\s+(?:found|available)|streams?\s+filtered|streams?\s+blocked|filtered)"#, options: [.caseInsensitive])

    /// trust.rs:80-85 — STATUS_LINE_RX.
    static let statusLineRX = try! NSRegularExpression(
        pattern: #"\b(?:expires?\s+in|days?\s+left|premium\s+(?:active|expir(?:ed|ing))|api\s+limit|quota\s+used)\b"#, options: [.caseInsensitive])

    /// trust.rs:87-88 — VIDEO_EXT_RX (url counts as "video" only for these
    /// extensions at query-string or end of string).
    static let videoExtRX = try! NSRegularExpression(
        pattern: #"\.(mkv|mp4|m4v|avi|webm|mov|ts)(\?|$)"#, options: [.caseInsensitive])

    /// trust.rs:90-95 — TRAILER_RX, matched against the lowercased
    /// "filename title name" haystack.
    static let trailerRX = try! NSRegularExpression(
        pattern: #"(?:^|[^a-z0-9])(?:trailer|teaser|tlr|trl|tra(?:iler)?|sneak[\s.\-_]?peek|preview|behind[\s.\-_]?the[\s.\-_]?scenes|featurette|making[\s.\-_]?of|deleted[\s.\-_]?scene|bloopers?|gag[\s.\-_]?reel|extras?|promo)(?:$|[^a-z0-9])"#, options: [.caseInsensitive])

    /// trust.rs:97-98 — SEQUEL_TAIL_RX (capture 1 = the trailing digit/roman token).
    static let sequelTailRX = try! NSRegularExpression(
        pattern: #"(?:\s|^)(\d{1,2}|[ivx]+)\s*$"#, options: [.caseInsensitive])

    /// trust.rs:100 — YEAR_PAREN_RX.
    static let yearParenRX = try! NSRegularExpression(pattern: #"\(\d{4}\)"#, options: [.caseInsensitive])

    /// trust.rs:102-103 — PART_WORD_RX.
    static let partWordRX = try! NSRegularExpression(pattern: #"\b(part|chapter|vol|volume)\b"#, options: [.caseInsensitive])

    /// trust.rs:105 — WORD_RX (runs on already-lowercased text).
    static let wordRX = try! NSRegularExpression(pattern: #"[a-z0-9]+"#, options: [.caseInsensitive])

    // trust.rs:107 — ANIME_JA_RX is defined in the Rust source but never used
    // (dead code, audit §8.1). Deliberately not ported.

    // MARK: - Roman / word helpers (trust.rs:118-131, 419-462)

    /// trust.rs:118-131 — roman_to_num.
    static func romanToNum(_ s: String) -> Int? {
        switch s {
        case "ii": return 2
        case "iii": return 3
        case "iv": return 4
        case "v": return 5
        case "vi": return 6
        case "vii": return 7
        case "viii": return 8
        case "ix": return 9
        case "x": return 10
        default: return nil
        }
    }

    private static let romanForSequel: [Int: String] = [
        2: "ii", 3: "iii", 4: "iv", 5: "v", 6: "vi", 7: "vii", 8: "viii", 9: "ix", 10: "x",
    ]
    private static let wordForSequel: [Int: String] = [
        2: "two", 3: "three", 4: "four", 5: "five", 6: "six", 7: "seven", 8: "eight",
        9: "nine", 10: "ten",
    ]

    /// trust.rs:419-461 — haystack_has_sequel_token.
    static func haystackHasSequelToken(_ haystack: String, expectedSeq: Int) -> Bool {
        let digit = String(expectedSeq)
        let roman = romanForSequel[expectedSeq]
        let word = wordForSequel[expectedSeq]
        for tok in wordRX.matchesAll(haystack) {
            if tok == digit { return true }
            if let roman, tok == roman { return true }
            if let word, tok == word { return true }
        }
        return false
    }

    // MARK: - Public entry point (trust.rs:138-158)

    /// trust.rs:138-158 — apply_trust. Rules are checked in exact order inside
    /// `checkOne`; the first match wins (one rejection per stream). `opts.disabled`
    /// short-circuits to keep-everything.
    static func applyTrust(
        streams: [ParsedStream],
        opts: TrustOptions
    ) -> (kept: [ParsedStream], rejected: [Rejection]) {
        if opts.disabled {
            return (kept: streams, rejected: [])
        }
        let strict = opts.strict
        let inCinemaWindow = isInCinemaWindow(releaseDate: opts.releaseDate)
        let olderCatalog = isOlderCatalog(releaseDate: opts.releaseDate, expectedYear: opts.expectedYear)

        var kept: [ParsedStream] = []
        kept.reserveCapacity(streams.count)
        var rejected: [Rejection] = []
        for s in streams {
            if let reason = checkOne(s, opts: opts, strict: strict,
                                     inCinemaWindow: inCinemaWindow, olderCatalog: olderCatalog) {
                rejected.append(Rejection(stream: s, reason: reason))
            } else {
                kept.append(s)
            }
        }
        return (kept: kept, rejected: rejected)
    }

    // MARK: - The 23 rules, exact order (trust.rs:160-399)

    static func checkOne(
        _ s: ParsedStream,
        opts: TrustOptions,
        strict: Bool,
        inCinemaWindow: Bool,
        olderCatalog: Bool
    ) -> String? {
        let st = s.stream

        // Rule 1 — no-playable-source (trust.rs:167-174).
        let hasPlayable = st.url != nil
            || st.infoHash != nil
            || st.ytId != nil
            || st.externalUrl != nil
            || hasNzbSource(s)   // D-TRUST-01: always false in the current contract.
        if !hasPlayable {
            return "no-playable-source"
        }

        // Rule 2 — addon-placeholder-banner (trust.rs:176-184).
        let titleNameDesc = "\(st.title ?? "") \(st.name ?? "") \(st.description ?? "")"
        if placeholderBannerRX.isMatch(titleNameDesc) {
            return "addon-placeholder-banner"
        }

        // Rule 3 — addon-status-card (trust.rs:185-209).
        // NOTE: the behaviorHints exemption reads `filename` ONLY (not the camelCase
        // `fileName`) — pinned by Rust test `status_card_camelcase_filename_not_exempted`.
        let urlIsVideo = st.url.map { videoExtRX.isMatch($0) } ?? false
        if st.infoHash == nil && !urlIsVideo && statusLineRX.isMatch(titleNameDesc) {
            let bh = st.behaviorHints
            let hasVideoSize = bh.map { ($0.videoSize ?? 0) != 0 } ?? false
            let hasFilename = bh.map { !($0.filename ?? "").isEmpty } ?? false
            if !hasVideoSize && !hasFilename {
                return "addon-status-card"
            }
        }

        let filename = (behaviorHintFilename(s) ?? "").lowercased()
        let titleLower = (st.title ?? "").lowercased()
        let nameLower = (st.name ?? "").lowercased()
        let haystack = "\(filename) \(titleLower) \(nameLower)"

        // Rule 4 — suspicious-extension:<ext> (trust.rs:211-220).
        for ext in filenameBlacklist where filename.hasSuffix(ext) {
            return "suspicious-extension:\(ext)"
        }

        // Rule 5 — trailer-or-extra (trust.rs:222-224).
        if trailerRX.isMatch(haystack) {
            return "trailer-or-extra"
        }

        // Rule 6 — addon-uncached-emoji (trust.rs:226-228).
        if uncachedEmojiRX.isMatch(titleNameDesc) {
            return "addon-uncached-emoji"
        }

        // Rule 7 — size-stub (trust.rs:230-234).
        if let sz = s.size, sz < tinyStubFloor {
            return "size-stub"
        }

        let kindIsMovie = opts.kind == "movie"
        let kindIsSeries = opts.kind == "series"

        // Rule 8 — movie-stub-too-small-for-{res} (trust.rs:239-249).
        // No short-format exemption here (matches Rust).
        if kindIsMovie, let sz = s.size {
            let floor = movieMinSize(s.resolution, inCinema: inCinemaWindow, older: olderCatalog)
            if sz < floor {
                return "movie-stub-too-small-for-\(resolutionLabel(s.resolution))"
            }
        }

        // Rules 9 & 10 — new-release-virus-{n}mb / new-release-stub-{n}mb
        // (trust.rs:251-264). sizeMB rounds half-away-from-zero, like Rust f64::round.
        if kindIsMovie && inCinemaWindow && !isTheaterSource(s.source),
           let sz = s.size {
            let sizeMB = UInt64((Double(sz) / Double(mib)).rounded())
            if sz < 250 * mib {
                return "new-release-virus-\(sizeMB)mb"
            }
            if sz < 500 * mib && !isShortFormat(s) {
                return "new-release-stub-\(sizeMB)mb"
            }
        }

        // Rule 11 — series-result-for-movie (trust.rs:266-269). Skipped for anime.
        if kindIsMovie && !opts.isAnime && (s.seasonPack || s.season != nil || s.episode != nil) {
            return "series-result-for-movie"
        }

        // Rule 12 — cinema-bare-untagged (trust.rs:271-281). Skipped for anime.
        if strict && kindIsMovie && !opts.isAnime && inCinemaWindow
            && opts.expectedYear != nil && s.year == nil
            && s.source == .other && s.resolution == .sd {
            return "cinema-bare-untagged"
        }

        // Rule 13 — title-mismatch (movie) (trust.rs:283-296).
        // NOTE: Rust does NOT skip this rule for anime (the audit §5.1 summary is
        // wrong here; §3.2's own condition table agrees with the code). Anime movies
        // ARE title-checked — parity follows trust.rs:283.
        if strict && kindIsMovie {
            if let expected = opts.expectedTitle, !s.parsedTitle.isEmpty,
               !titleMatches(expected: expected, parsed: s.parsedTitle,
                             parsedYear: s.year, expectedYear: opts.expectedYear) {
                return "title-mismatch"
            }
        }

        // Rule 14 — cinema-year-mismatch:{s}-vs-{e} (trust.rs:298-304).
        if strict && kindIsMovie && inCinemaWindow,
           let sy = s.year, let ey = opts.expectedYear, sy != ey {
            return "cinema-year-mismatch:\(sy)-vs-\(ey)"
        }

        // Rule 15 — filename-missing-sequel (trust.rs:306-318).
        // Haystack = lowercased filename + raw title, lowercased as a whole.
        if strict && kindIsMovie,
           let expected = opts.expectedTitle,
           let expectedSeq = sequelMarker(expected), expectedSeq >= 2 {
            let titleStr = st.title ?? ""
            let sequelHaystack = "\(filename) \(titleStr)".lowercased()
            if !haystackHasSequelToken(sequelHaystack, expectedSeq: expectedSeq) {
                return "filename-missing-sequel"
            }
        }

        // Rules 16-18 — fresh-cinema-fake-{bluray,4k-web,hdtv} (trust.rs:320-337).
        if strict && kindIsMovie && inCinemaWindow {
            if s.source == .bluRay || s.remux {
                return "fresh-cinema-fake-bluray"
            }
            if s.resolution == .uhd
                && (s.source == .webDl || s.source == .webRip
                    || s.source == .bdRip || s.source == .hdRip) {
                return "fresh-cinema-fake-4k-web"
            }
            if s.source == .hdtv && (s.resolution == .uhd || s.resolution == .p1080) {
                return "fresh-cinema-fake-hdtv"
            }
        }

        // Rule 19 — episode-stub-too-small-for-{res} (trust.rs:339-355).
        // Short-format exempt; anime uses the smaller anime table.
        if kindIsSeries, let sz = s.size, !isShortFormat(s) {
            let floor = opts.isAnime
                ? animeEpisodeMinSize(s.resolution, inCinema: inCinemaWindow, older: olderCatalog)
                : episodeMinSize(s.resolution, inCinema: inCinemaWindow, older: olderCatalog)
            if sz < floor {
                return "episode-stub-too-small-for-\(resolutionLabel(s.resolution))"
            }
        }

        // Rule 20 — title-mismatch (series) (trust.rs:357-370). Skipped for anime.
        if strict && kindIsSeries && !opts.isAnime {
            if let expected = opts.expectedTitle, !s.parsedTitle.isEmpty,
               !titleMatches(expected: expected, parsed: s.parsedTitle,
                             parsedYear: s.year, expectedYear: opts.expectedYear) {
                return "title-mismatch"
            }
        }

        let hasFileIdx = st.fileIdx != nil

        // Rule 21 — season-mismatch:{s}-vs-{e} (trust.rs:374-382).
        // Applies regardless of kind (no kind gate in Rust); skipped for anime,
        // for fileIdx streams, and for season packs. NOTE: opts.allowSeasonPacks is
        // dead in the Rust trust gate — the exemption is the stream's own
        // seasonPack flag (pinned by Rust test `allows_season_pack_when_flag_set`).
        if strict && !opts.isAnime && !hasFileIdx && !s.seasonPack {
            if let expectedSeason = opts.expectedSeason, let season = s.season,
               season != expectedSeason {
                return "season-mismatch:\(season)-vs-\(expectedSeason)"
            }
        }

        // Rule 22 — episode-mismatch:{s}-vs-{e} (trust.rs:384-392). Same gate.
        if strict && !opts.isAnime && !hasFileIdx && !s.seasonPack {
            if let expectedEpisode = opts.expectedEpisode, let episode = s.episode,
               episode != expectedEpisode {
                return "episode-mismatch:\(episode)-vs-\(expectedEpisode)"
            }
        }

        // Rule 23 — scam-score-{n} (trust.rs:394-396).
        if s.scamScore >= 5 && !opts.allowCam && !olderCatalog {
            return "scam-score-\(s.scamScore)"
        }

        return nil
    }

    // MARK: - D-TRUST-01 (resolved: EngineStream now carries the extra bag)

    /// Rust `check_one` counts `stream.extra["nzbUrl"]` as a fifth playable source
    /// (trust.rs:171). Wire-through: EngineStream.extra (added with the vector harness).
    static func hasNzbSource(_ s: ParsedStream) -> Bool {
        guard let extra = s.stream.extra else { return false }
        return extra["nzbUrl"]?.isEmpty == false
    }

    // MARK: - behaviorHints helpers (trust.rs:401-417)

    /// trust.rs:401-406 — behavior_hint_filename: `filename` wins, else `fileName`.
    static func behaviorHintFilename(_ s: ParsedStream) -> String? {
        guard let bh = s.stream.behaviorHints else { return nil }
        return bh.filename ?? bh.fileName
    }

    /// trust.rs:408-417 — is_short_format: SHORT_FORMAT_RX on "filename title name".
    static func isShortFormat(_ s: ParsedStream) -> Bool {
        let filename = behaviorHintFilename(s) ?? ""
        let haystack = "\(filename) \(s.stream.title ?? "") \(s.stream.name ?? "")"
        return shortFormatRX.isMatch(haystack)
    }

    // MARK: - Size floors (trust.rs:17-48; audit §3.3)
    // All values are binary MiB; every floor is given as the exact byte count.

    /// Movie floors — (cinema, normal, older):
    ///   4K     2560 / 1536 /  600 MiB
    ///   1080p  ⌈6GiB/5⌉ = 1,288,490,189 B / 700 / 250 MiB
    ///   720p   600 /  400 /  120 MiB
    ///   480p   250 /  150 /   50 MiB
    ///   SD     200 /  100 /   25 MiB
    /// Selection: older > cinema > normal (trust.rs:25).
    static func movieMinSize(_ r: Resolution, inCinema: Bool, older: Bool) -> UInt64 {
        let floors: (cinema: UInt64, normal: UInt64, older: UInt64) = {
            switch r {
            case .uhd:   return (2560 * mib, 1536 * mib, 600 * mib)
            case .p1080: return (movie1080pCinemaFloor, 700 * mib, 250 * mib)
            case .p720:  return (600 * mib, 400 * mib, 120 * mib)
            case .p480:  return (250 * mib, 150 * mib, 50 * mib)
            case .sd:    return (200 * mib, 100 * mib, 25 * mib)
            }
        }()
        return older ? floors.older : (inCinema ? floors.cinema : floors.normal)
    }

    /// Episode floors (non-anime) — (cinema, normal, older):
    ///   4K     1024 / 600 / 200 MiB
    ///   1080p   400 / 250 / 100 MiB
    ///   720p    200 / 120 /  40 MiB
    ///   480p     80 /  50 /  12 MiB
    ///   SD       50 /  30 /   8 MiB
    static func episodeMinSize(_ r: Resolution, inCinema: Bool, older: Bool) -> UInt64 {
        let floors: (cinema: UInt64, normal: UInt64, older: UInt64) = {
            switch r {
            case .uhd:   return (1024 * mib, 600 * mib, 200 * mib)
            case .p1080: return (400 * mib, 250 * mib, 100 * mib)
            case .p720:  return (200 * mib, 120 * mib, 40 * mib)
            case .p480:  return (80 * mib, 50 * mib, 12 * mib)
            case .sd:    return (50 * mib, 30 * mib, 8 * mib)
            }
        }()
        return older ? floors.older : (inCinema ? floors.cinema : floors.normal)
    }

    /// Anime episode floors — (cinema, normal, older):
    ///   4K     600 / 400 / 150 MiB
    ///   1080p   220 / 150 /  50 MiB
    ///   720p    100 /  60 /  20 MiB
    ///   480p     40 /  28 /   8 MiB
    ///   SD       25 /  18 /   5 MiB
    static func animeEpisodeMinSize(_ r: Resolution, inCinema: Bool, older: Bool) -> UInt64 {
        let floors: (cinema: UInt64, normal: UInt64, older: UInt64) = {
            switch r {
            case .uhd:   return (600 * mib, 400 * mib, 150 * mib)
            case .p1080: return (220 * mib, 150 * mib, 50 * mib)
            case .p720:  return (100 * mib, 60 * mib, 20 * mib)
            case .p480:  return (40 * mib, 28 * mib, 8 * mib)
            case .sd:    return (25 * mib, 18 * mib, 5 * mib)
            }
        }()
        return older ? floors.older : (inCinema ? floors.cinema : floors.normal)
    }

    /// Combined lookup mirroring the Rust dispatch: `kind == "movie"` uses the
    /// movie table; any other kind uses the anime table when `isAnime`, else the
    /// episode table. (The episode tables are only consulted for
    /// `kind == "series"` by `checkOne`, exactly like Rust.)
    static func sizeFloor(
        kind: String?,
        resolution: Resolution,
        window: CatalogWindow,
        isAnime: Bool
    ) -> UInt64 {
        let inCinema = window == .cinema
        let older = window == .older
        if kind == "movie" {
            return movieMinSize(resolution, inCinema: inCinema, older: older)
        }
        return isAnime
            ? animeEpisodeMinSize(resolution, inCinema: inCinema, older: older)
            : episodeMinSize(resolution, inCinema: inCinema, older: older)
    }

    /// trust.rs:50-58 — resolution_label (matches the Swift rawValues).
    static func resolutionLabel(_ r: Resolution) -> String { r.rawValue }

    static func isTheaterSource(_ s: Source) -> Bool {
        s == .cam || s == .ts || s == .hdts || s == .tc
    }

    // MARK: - Title matching (trust.rs:464-568)

    /// trust.rs:464-478 — sequel_marker: strip `(YYYY)` and part/chapter/vol/volume
    /// words, then read a trailing `\d{1,2}` (2...20) or roman `ii..x` token.
    static func sequelMarker(_ title: String) -> Int? {
        var cleaned = yearParenRX.stringByReplacingMatches(
            in: title, options: [], range: NSRange(location: 0, length: (title as NSString).length),
            withTemplate: "")
        cleaned = partWordRX.stringByReplacingMatches(
            in: cleaned, options: [], range: NSRange(location: 0, length: (cleaned as NSString).length),
            withTemplate: "")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullRange = NSRange(location: 0, length: (trimmed as NSString).length)
        guard let m = sequelTailRX.firstMatch(in: trimmed, options: [], range: fullRange),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: trimmed) else { return nil }
        let tok = String(trimmed[r]).lowercased()
        if tok.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }) {
            guard let n = Int(tok), (2...20).contains(n) else { return nil }
            return n
        }
        return romanToNum(tok)
    }

    /// trust.rs:480-492 — year_tolerance_for: age = currentYear − expectedYear;
    /// ≥30 → 4, ≥15 → 3, ≥5 → 2, else 1.
    static func yearToleranceFor(expectedYear: Int?) -> Int {
        guard let ey = expectedYear else { return 1 }
        let age = currentYear() - ey
        if age >= 30 { return 4 }
        if age >= 15 { return 3 }
        if age >= 5 { return 2 }
        return 1
    }

    /// trust.rs:494-548 — title_matches.
    static func titleMatches(
        expected: String,
        parsed: String,
        parsedYear: Int?,
        expectedYear: Int?
    ) -> Bool {
        let expectedSeq = sequelMarker(expected)
        let parsedSeq = sequelMarker(parsed)
        let tolerance = yearToleranceFor(expectedYear: expectedYear)

        if let e = expectedSeq, let p = parsedSeq, e != p {
            return false
        }
        if expectedSeq != nil && parsedSeq == nil {
            guard let py = parsedYear, let ey = expectedYear else { return false }
            if abs(py - ey) > tolerance { return false }
        }
        if expectedSeq == nil, let ps = parsedSeq, ps >= 2 {
            guard let py = parsedYear, let ey = expectedYear else { return false }
            if abs(py - ey) > tolerance { return false }
        }

        let expectedTokens = tokenize(expected)
        let parsedTokens = tokenize(parsed)
        if expectedTokens.isEmpty || parsedTokens.isEmpty {
            return true
        }
        let expectedSet = Set(expectedTokens)
        let parsedSet = Set(parsedTokens)
        let overlap = countOverlap(expectedTokens, lookup: parsedSet)
        let reverseOverlap = countOverlap(parsedTokens, lookup: expectedSet)
        let expectedRatio = Double(overlap) / Double(expectedTokens.count)
        let parsedRatio = Double(reverseOverlap) / Double(parsedTokens.count)

        // Short-title guard (trust.rs:544-546): expected has ≤2 tokens and the
        // parsed title carries >2 tokens that don't overlap → reject (e.g.
        // "Obsession" vs "DBM Obsession Viva Las Vegas").
        if expectedTokens.count <= 2 && max(0, parsedTokens.count - overlap) > 2 {
            return false
        }
        return expectedRatio >= 0.5 || parsedRatio >= 0.5 || overlap >= 2
    }

    /// trust.rs:550-568 — count_overlap: exact word, or prefix-overlap of words
    /// ≥ 4 chars (either direction).
    static func countOverlap(_ words: [String], lookup: Set<String>) -> Int {
        var hits = 0
        for w in words {
            if lookup.contains(w) {
                hits += 1
                continue
            }
            for l in lookup where w.count >= 4 && l.count >= 4
                && (w.hasPrefix(l) || l.hasPrefix(w)) {
                hits += 1
                break
            }
        }
        return hits
    }

    /// trust.rs:570-585 — tokenize: lowercase → NFKD → strip U+0300-U+036F →
    /// [a-z0-9]+ words → drop len < 3 and stopwords.
    static func tokenize(_ text: String) -> [String] {
        let lower = text.lowercased()
        let nfkd = lower.decomposedStringWithCompatibilityMapping
        let filtered = nfkd.unicodeScalars.filter { !(0x0300...0x036F).contains($0.value) }
        let stripped = String(filtered.map(Character.init))
        return wordRX.matchesAll(stripped)
            .filter { $0.count >= 3 && !titleStopwords.contains($0) }
    }

    // MARK: - Dates (trust.rs:587-660)

    /// trust.rs:587-601 — parse_iso_date_to_unix_ms: trim; cut at first 'T'/' ';
    /// split on '-'; y/m/d must parse and satisfy 1≤m≤12, 1≤d≤31. NOTE (Rust
    /// parity): the day is NOT validated against the month (2025-02-31 parses),
    /// and extra segments after day are ignored.
    static func parseISODateToUnixMs(_ s: String) -> Int64? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        var datePart = trimmed
        if let idx = trimmed.firstIndex(where: { $0 == "T" || $0 == " " }) {
            datePart = String(trimmed[..<idx])
        }
        let parts = datePart.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count >= 3,
              let y = Int64(parts[0]), let m = Int64(parts[1]), let d = Int64(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        return daysFromCivil(y: y, m: m, d: d) * 86_400_000
    }

    /// trust.rs:603-611 — days_from_civil (Howard Hinnant's civil-date algorithm).
    static func daysFromCivil(y: Int64, m: Int64, d: Int64) -> Int64 {
        let yy = m <= 2 ? y - 1 : y
        let era = (yy >= 0 ? yy : yy - 399) / 400
        let yoe = yy - era * 400
        let mp = m > 2 ? m - 3 : m + 9
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// trust.rs:613-618 — now_unix_ms.
    static func nowUnixMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000.0)
    }

    /// trust.rs:620-624 — current_year (via the civil algorithm, no locale).
    static func currentYear() -> Int {
        Int(civilFromDays(nowUnixMs() / 86_400_000).year)
    }

    /// trust.rs:626-638 — civil_from_days (inverse of days_from_civil).
    static func civilFromDays(_ days: Int64) -> (year: Int64, month: Int, day: Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let yr = m <= 2 ? y + 1 : y
        return (yr, Int(m), Int(d))
    }

    /// trust.rs:640-647 — is_in_cinema_window: -90 < days < 60 (strict).
    static func isInCinemaWindow(releaseDate: String?) -> Bool {
        guard let s = releaseDate, let ts = parseISODateToUnixMs(s) else { return false }
        let days = Double(nowUnixMs() - ts) / 86_400_000.0
        return days > -90.0 && days < 60.0
    }

    /// trust.rs:649-660 — is_older_catalog: release date > 730 days ago (early
    /// return), else current_year − expected_year > 2.
    static func isOlderCatalog(releaseDate: String?, expectedYear: Int?) -> Bool {
        if let s = releaseDate, let ts = parseISODateToUnixMs(s) {
            let days = Double(nowUnixMs() - ts) / 86_400_000.0
            return days > 365.0 * 2.0
        }
        if let ey = expectedYear {
            return currentYear() - ey > 2
        }
        return false
    }

    /// Convenience: the single-window resolution used by `sizeFloor`.
    static func catalogWindow(releaseDate: String?, expectedYear: Int?) -> CatalogWindow {
        if isOlderCatalog(releaseDate: releaseDate, expectedYear: expectedYear) { return .older }
        if isInCinemaWindow(releaseDate: releaseDate) { return .cinema }
        return .normal
    }
}

// MARK: - Catalog window (trust.rs floor selection: older > cinema > normal)

/// Which size-floor column applies to a given catalog context.
enum CatalogWindow: String, Equatable, Sendable {
    /// Release date within −90...+60 days of now (trust.rs:640-647).
    case cinema
    /// Default: everything not cinema and not older.
    case normal
    /// Release date > 730 days ago, or currentYear − expectedYear > 2 (trust.rs:649-660).
    case older
}

// MARK: - NSRegularExpression helpers

extension NSRegularExpression {
    /// All full-match substrings, in order.
    func matchesAll(_ string: String) -> [String] {
        let ns = string as NSString
        let range = NSRange(location: 0, length: ns.length)
        return matches(in: string, options: [], range: range).map { ns.substring(with: $0.range) }
    }

    func isMatch(_ string: String) -> Bool {
        firstMatch(in: string, options: [],
                   range: NSRange(location: 0, length: (string as NSString).length)) != nil
    }
}
