import Foundation

// MARK: - Stream scoring. Mirror of `harbor-core/src/scoring.rs` (Rust truth).
//
// Every function below mirrors a Rust counterpart 1:1 (Rust fn → Swift):
//   compute_corpus_stats          (scoring.rs:198)  → computeCorpusStats
//   resolution_points             (scoring.rs:282)  → resolutionPoints / resolutionReason
//   audio_points                  (scoring.rs:307)  → audioPoints
//   trusted_addon_points          (scoring.rs:332)  → trustedAddonPoints
//   addon_priority_points         (scoring.rs:355)  → addonPriorityPoints
//   playability_penalty           (scoring.rs:371)  → playabilityPenalty
//   tier_of                       (scoring.rs:393)  → tierOf
//   cam_in_filename_penalty       (scoring.rs:421)  → camInFilenamePenalty
//   expected_min_size_bytes       (scoring.rs:457)  → expectedMinSizeBytes
//   size_mislabel_penalty         (scoring.rs:471)  → sizeMislabelPenalty
//   undersized_new_release_penalty(scoring.rs:503)  → undersizedNewReleasePenalty
//   bitrate_budget_penalty        (scoring.rs:580)  → bitrateBudgetPenalty
//   impossibly_small_movie_penalty(scoring.rs:635)  → impossiblySmallMoviePenalty
//   fresh_theatrical_adjust       (scoring.rs:703)  → freshTheatricalAdjust
//   score_stream                  (scoring.rs:836)  → scoreStream
//
// Parity notes (see docs/audit/stream-engine.md §4):
//   - Scores are Double; every applied delta is recorded as ScoreReason and appended
//     to `reasons` only when delta != 0 (Rust scoring.rs:869, 887-903, 906…).
//   - TS `preferAac` does NOT exist in the Rust contract and is intentionally absent.
//   - `ScoreOptions.inTheaters` is not consumed by Rust scoring and is unused here.
//   - The Rust CorpusStats percentile fields (medianSize/p90Size/p10Seeders/p90Seeders)
//     are not consumed by any scoring function; the canonical Swift CorpusStats
//     (EngineModels.swift) omits them, so they are not computed.

/// Deterministic port of Harbor's Rust scoring (`scoring.rs`).
/// Pure functions: same inputs always produce the same score/reasons/tier.
enum Scoring {

    // MARK: - Constants (scoring.rs:23-25, 352-353)

    static let trackingMinSeeders: UInt32 = 30
    static let shortFreshDays = 30.0
    static let theaterWindowDays = 150.0
    static let addonPriorityMax = 12.0
    static let addonPriorityStep = 4.0

    /// scoring.rs:27-36 — trusted release-group list (exact-match, as authored in Rust).
    static let trustedGroups: Set<String> = [
        "FRDS", "FRAMESTOR", "FORM", "EVO", "RARBG", "ETHEL", "FLUX", "QXR", "MEGUSTA", "ION10",
        "PSA", "AMIABLE", "GALAXYRG", "WEBDV", "RZEROX", "SIC", "TGX", "NTB", "NTG", "TEPES",
        "GECKOS", "SUCCESSFULCRAB", "SUBSPLEASE", "ERAI", "ERAIRAWS", "JUDAS", "ASW", "EMBER",
        "ANE", "CLEO", "BEATRICERAWS", "AKIHITO", "VODES", "NANDESUKA", "SMOL", "TENRAISENSEI",
        "GST", "ANIMEKAIZOKU", "REINFORCE", "RAWS", "OZR", "PURGATORY", "SHK", "KOTUWA", "KIRION",
        "COMMIE", "DAMEDESUYO", "MTBB", "GJM", "SOFCJ",
    ]

    /// scoring.rs:45 — lossy release groups exempt from the size-mismatch penalty.
    static let lossyTrustedGroups: Set<String> = ["YTS", "YIFY", "YTSAG", "YTS-AG"]

    // MARK: - Regexes (scoring.rs:47-56)

    /// scoring.rs:47-49 — `(?i)\b(?:cam|hdcam|hd[\s._-]?cam|tsrip|telesync|hdts|hd[\s._-]?ts|telecine|hd[\s._-]?tc|hc[\s._-]?hdrip|hc[\s._-]?cam|new[\s._-]?cam|cleancam|hqcam)\b`
    static let camMarkerRegex = try! NSRegularExpression(
        pattern: "\\b(?:cam|hdcam|hd[\\s._-]?cam|tsrip|telesync|hdts|hd[\\s._-]?ts|telecine|hd[\\s._-]?tc|hc[\\s._-]?hdrip|hc[\\s._-]?cam|new[\\s._-]?cam|cleancam|hqcam)\\b",
        options: [.caseInsensitive]
    )

    /// scoring.rs:51 — `(?i)easynews`
    static let easynewsRegex = try! NSRegularExpression(pattern: "easynews", options: [.caseInsensitive])

    /// scoring.rs:53-54 — trusted addon name.
    static let trustedAddonRegex = try! NSRegularExpression(
        pattern: "mediafusion|comet|easynews|torrentio", options: [.caseInsensitive]
    )

    /// scoring.rs:55-56 — strong addon name.
    static let strongAddonRegex = try! NSRegularExpression(
        pattern: "mediafusion|comet", options: [.caseInsensitive]
    )

    // MARK: - Public API

    /// scoring.rs:198-242 — corpus statistics over the parsed stream pool.
    ///
    /// `isTracked` (scoring.rs:201-207) = cached on any active debrid OR `url` present
    /// OR seeders >= 30. Theater = tracked with source CAM/TS/HDTS/TC; webish = tracked
    /// with source WEB-DL/WEBRip/BluRay/BDRip. theater/webish fractions divide by
    /// `max(trackedCount, 1)` (÷1 when zero tracked); `trustedTrackedFraction` divides by
    /// `max(streams.count, 1)`. The Rust percentile side-products are intentionally not
    /// computed (the canonical Swift CorpusStats has no fields for them and nothing
    /// consumes them).
    static func computeCorpusStats(streams: [ParsedStream], opts: ScoreOptions) -> CorpusStats {
        let days = daysSince(opts.releaseDate)

        let tracked = streams.filter { isTracked($0, opts) }
        let trustedTrackedCount = tracked.count
        let theater = tracked.filter { isTheaterSource($0.source) }.count
        let webish = tracked.filter { isWebishSource($0.source) }.count

        let total = max(trustedTrackedCount, 1)
        let denom = max(streams.count, 1)

        return CorpusStats(
            daysSinceRelease: days,
            trustedTrackedFraction: Double(trustedTrackedCount) / Double(denom),
            theaterCaptureFraction: Double(theater) / Double(total),
            webishFraction: Double(webish) / Double(total),
            trustedTrackedCount: trustedTrackedCount
        )
    }

    /// scoring.rs:282-305 — resolution delta. 4K +25, 1080p +20, 720p +8, 480p +2, SD +0.
    static func resolutionPoints(_ r: Resolution) -> Double {
        switch r {
        case .uhd: return 25.0
        case .p1080: return 20.0
        case .p720: return 8.0
        case .p480: return 2.0
        case .sd: return 0.0
        }
    }

    /// scoring.rs:393-419 — tier assignment:
    /// 1. Source ∈ {CAM, TS, HDTS, TC, SCR} → ROUGH
    /// 2. 4K + (DV|DV+HDR10) → 4K_DV; 4K + any HDR → 4K_HDR; 4K → 4K
    /// 3. 1080p + HDR → 1080p_HDR; 1080p → 1080p
    /// 4. 720p → 720p
    /// 5. else → SD
    static func tierOf(parsed: ParsedStream) -> Tier {
        switch parsed.source {
        case .cam, .ts, .hdts, .tc, .scr:
            return .rough
        default:
            break
        }
        switch parsed.resolution {
        case .uhd:
            if let hdr = parsed.hdrFormat, hdr == .dv || hdr == .dvHdr10 { return .uhdDv }
            if parsed.hdrFormat != nil { return .uhdHdr }
            return .uhd
        case .p1080:
            if parsed.hdrFormat != nil { return .p1080Hdr }
            return .p1080
        case .p720:
            return .p720
        case .p480, .sd:
            return .sd
        }
    }

    /// scoring.rs:836-1233 — full stream score with reasons, in Rust application order.
    static func scoreStream(parsed: ParsedStream, opts: ScoreOptions, corpus: CorpusStats) -> ScoredStream {
        var reasons: [ScoreReason] = []
        var score = 0.0

        // scoring.rs:844-866 — cached / easynews-direct / direct url.
        let cached = isCachedOnActive(parsed, opts.activeDebrids)
        let directPlayable = parsed.stream.url != nil
        let easynewsInAddon = regexMatches(easynewsRegex, parsed.stream.addonName)
        let easynewsInTitle = regexMatches(easynewsRegex, parsed.parsedTitle)
        let isEasynews = easynewsInAddon || easynewsInTitle

        if cached || isEasynews {
            score += 60.0
            reasons.append(ScoreReason(signal: cached ? "cached" : "easynews-direct", delta: 60.0))
        } else if directPlayable {
            score += 25.0
            reasons.append(ScoreReason(signal: "direct url", delta: 25.0))
        }

        // scoring.rs:868-872 — resolution.
        let resBoost = resolutionReason(parsed.resolution)
        if resBoost.delta != 0 {
            score += resBoost.delta
            reasons.append(resBoost)
        }

        // scoring.rs:874-885 — HDR. DV/DV+HDR10 +6, anything else +5.
        if let hdr = parsed.hdrFormat {
            let hdrDelta: Double = (hdr == .dvHdr10 || hdr == .dv) ? 6.0 : 5.0
            score += hdrDelta
            reasons.append(ScoreReason(signal: hdrLabel(hdr), delta: hdrDelta))
        }

        // scoring.rs:887-903 — codec.
        switch parsed.codec {
        case .hevc:
            score += 1.0
            reasons.append(ScoreReason(signal: "HEVC", delta: 1.0))
        case .av1:
            score += 1.0
            reasons.append(ScoreReason(signal: "AV1", delta: 1.0))
        default:
            break
        }

        // scoring.rs:905-909 — audio codec.
        let audioDelta = audioPoints(parsed.audio)
        if audioDelta.delta != 0 {
            score += audioDelta.delta
            reasons.append(audioDelta)
        }

        // scoring.rs:911-917 — channel count.
        if parsed.audio.channels >= 6 {
            score += 2.0
            reasons.append(ScoreReason(signal: "\(parsed.audio.channels).0 channels", delta: 2.0))
        }

        // scoring.rs:919-939 — seeders (only when not cached).
        if !cached, let seeders = parsed.seeders {
            let seedDelta = min(Int(seeders) / 10, 10)
            if seedDelta > 0 {
                score += Double(seedDelta)
                reasons.append(ScoreReason(signal: "seeders=\(seeders)", delta: Double(seedDelta)))
            } else if parsed.stream.url == nil, parsed.stream.infoHash != nil, seeders == 0 {
                score -= 20.0
                reasons.append(ScoreReason(signal: "zero-seeders-stale-meta", delta: -20.0))
            }
        }

        // scoring.rs:941-947 — stacks with the stale-meta penalty above.
        if parsed.stream.infoHash != nil, parsed.seeders == 0, !cached {
            score -= 8.0
            reasons.append(ScoreReason(signal: "zero-seeders-soft", delta: -8.0))
        }

        // scoring.rs:949-981 — year mismatch. "recent" = release date within 365 days.
        let expectedYear = opts.releaseDate.flatMap { (date: String) -> Int? in
            guard date.count >= 4 else { return nil }
            return Int(date.prefix(4))
        }
        if let ey = expectedYear, let sy = parsed.year {
            let diff = abs(sy - ey)
            if diff != 0 {
                let daysFromRelease = opts.releaseDate
                    .flatMap(parseISODateToMs)
                    .map { abs((currentTimeMs() - $0) / 86_400_000.0) }
                    ?? .infinity
                let isRecent = daysFromRelease < 365.0
                let suffix = isRecent ? "-recent" : ""
                if diff == 1 {
                    let delta = isRecent ? -75.0 : -18.0
                    score += delta
                    reasons.append(ScoreReason(signal: "year-off-by-1:\(sy)vs\(ey)\(suffix)", delta: delta))
                } else {
                    let delta = isRecent ? -150.0 : -70.0
                    score += delta
                    reasons.append(ScoreReason(signal: "year-mismatch:\(sy)vs\(ey)\(suffix)", delta: delta))
                }
            }
        }

        // scoring.rs:983-992 — trusted release group.
        if let group = parsed.releaseGroupNormalized, trustedGroups.contains(group) {
            score += 2.0
            reasons.append(ScoreReason(signal: "group:\(group)", delta: 2.0))
        }

        // scoring.rs:994-1005 — previous-episode release group (exact string equality).
        if let preferred = opts.preferredReleaseGroup,
           let group = parsed.releaseGroupNormalized,
           group == preferred {
            score += 8.0
            reasons.append(ScoreReason(signal: "prev-episode-group:\(group)", delta: 8.0))
        }

        // scoring.rs:1007-1013 — REMUX flag.
        if parsed.remux {
            score += 3.0
            reasons.append(ScoreReason(signal: "REMUX", delta: 3.0))
        }

        // scoring.rs:1015-1045 — theater-ish source penalties.
        switch parsed.source {
        case .cam:
            score -= 80.0
            reasons.append(ScoreReason(signal: "CAM penalty", delta: -80.0))
        case .ts, .hdts:
            score -= 60.0
            reasons.append(ScoreReason(signal: "Telesync penalty", delta: -60.0))
        case .tc:
            score -= 50.0
            reasons.append(ScoreReason(signal: "Telecine penalty", delta: -50.0))
        case .scr:
            score -= 40.0
            reasons.append(ScoreReason(signal: "Screener penalty", delta: -40.0))
        default:
            break
        }

        // scoring.rs:1047-1061 — PROPER / REPACK{n} → +min(2, iteration || 1).
        if parsed.proper || parsed.repackIteration > 0 {
            let base = parsed.repackIteration == 0 ? 1 : parsed.repackIteration
            let r = Double(min(2, base))
            score += r
            let signal = parsed.proper ? "PROPER" : "REPACK\(parsed.repackIteration)"
            reasons.append(ScoreReason(signal: signal, delta: r))
        }

        // scoring.rs:1063-1126 — language heuristics.
        let preferred = opts.preferredLanguages
        if !preferred.isEmpty {
            if parsed.audioLanguages.isEmpty {
                score -= 3.0
                reasons.append(ScoreReason(signal: "language-unknown", delta: -3.0))
            } else {
                let isMulti = parsed.audioLanguages.contains { $0 == "Multi" }
                var matched = false
                for language in parsed.audioLanguages {
                    let lower = language.lowercased()
                    for p in preferred {
                        let pref = p.lowercased()
                        if lower == pref || lower.hasPrefix(pref) {
                            matched = true
                            break
                        }
                    }
                    if matched { break }
                }
                if matched {
                    score += 12.0
                    reasons.append(ScoreReason(signal: "preferred-language", delta: 12.0))
                } else if isMulti {
                    if opts.preferSingleAudioTrack {
                        score -= 18.0
                        reasons.append(ScoreReason(signal: "html5-multi-audio-penalty", delta: -18.0))
                    } else {
                        score += 4.0
                        reasons.append(ScoreReason(signal: "multi-language", delta: 4.0))
                    }
                } else {
                    score -= 14.0
                    reasons.append(ScoreReason(signal: "language-mismatch", delta: -14.0))
                }
            }
        } else if opts.preferSingleAudioTrack, parsed.audioLanguages.contains(where: { $0 == "Multi" }) {
            score -= 12.0
            reasons.append(ScoreReason(signal: "html5-multi-audio-penalty", delta: -12.0))
        }

        // scoring.rs:1128-1135 — scam score.
        if parsed.scamScore > 0 {
            let s = Double(parsed.scamScore)
            score -= s
            reasons.append(ScoreReason(signal: "scam-penalty", delta: -s))
        }

        // scoring.rs:1137-1143 — prelinked url.
        if parsed.stream.url != nil, !cached {
            score += 4.0
            reasons.append(ScoreReason(signal: "prelinked-url", delta: 4.0))
        }

        // scoring.rs:1145-1153 — origin addon (dominant signal).
        if let pref = opts.preferAddonId, parsed.stream.addonId == pref {
            score += 250.0
            reasons.append(ScoreReason(signal: "origin-addon", delta: 250.0))
        }

        // scoring.rs:1155-1159 — trusted/strong addon.
        let trustedAddonBoost = trustedAddonPoints(parsed)
        if trustedAddonBoost.delta > 0.0 {
            score += trustedAddonBoost.delta
            reasons.append(trustedAddonBoost)
        }

        // scoring.rs:1161-1165 — addon priority.
        let addonPriorityBoost = addonPriorityPoints(parsed)
        if addonPriorityBoost.delta > 0.0 {
            score += addonPriorityBoost.delta
            reasons.append(addonPriorityBoost)
        }

        // scoring.rs:1167-1174 — playability (single reason, sums internally).
        let playabilityDelta = playabilityPenalty(parsed)
        if playabilityDelta < 0.0 {
            score += playabilityDelta
            reasons.append(ScoreReason(signal: "webview2-unfriendly", delta: playabilityDelta))
        }

        // scoring.rs:1176-1180 — bitrate budget.
        let bitratePenalty = bitrateBudgetPenalty(parsed, opts, cached: cached)
        if bitratePenalty.delta < 0.0 {
            score += bitratePenalty.delta
            reasons.append(bitratePenalty)
        }

        // scoring.rs:1182-1197 — size mismatch vs runtime-derived minimum.
        let expectedMin = opts.runtimeMinutes.flatMap { expectedMinSizeBytes(parsed.resolution, $0) }
        let hasValidSize: Bool
        if let sz = parsed.size, let minSize = expectedMin {
            hasValidSize = Double(sz) >= minSize
        } else {
            hasValidSize = false
        }
        let sizePenalty = sizeMislabelPenalty(parsed, expectedMin)
        if sizePenalty < 0.0 {
            score += sizePenalty
            reasons.append(ScoreReason(signal: "size-mismatch", delta: sizePenalty))
        }

        // scoring.rs:1199-1206 — hires title vs cam filename.
        let desyncPenalty = camInFilenamePenalty(parsed)
        if desyncPenalty < 0.0 {
            score += desyncPenalty
            reasons.append(ScoreReason(signal: "title-says-hires-filename-says-cam", delta: desyncPenalty))
        }

        // scoring.rs:1208-1212 — undersized new release.
        let undersizedPenalty = undersizedNewReleasePenalty(parsed, opts)
        if undersizedPenalty.delta < 0.0 {
            score += undersizedPenalty.delta
            reasons.append(undersizedPenalty)
        }

        // scoring.rs:1214-1218 — impossibly small movie.
        let tinyPenalty = impossiblySmallMoviePenalty(parsed, opts)
        if tinyPenalty.delta < 0.0 {
            score += tinyPenalty.delta
            reasons.append(tinyPenalty)
        }

        // scoring.rs:1220-1224 — fresh theatrical window (applied when delta != 0).
        let recency = freshTheatricalAdjust(parsed, opts, hasValidSize: hasValidSize, corpus: corpus)
        if recency.delta != 0.0 {
            score += recency.delta
            reasons.append(recency)
        }

        // scoring.rs:1226-1232.
        let tier = tierOf(parsed: parsed)
        return ScoredStream(parsed: parsed, score: score, reasons: reasons, tier: tier)
    }

    // MARK: - Internal helpers shared with Ranking

    /// scoring.rs:58-60 — CAM/TS/HDTS/TC.
    static func isTheaterSource(_ source: Source) -> Bool {
        switch source {
        case .cam, .ts, .hdts, .tc: return true
        default: return false
        }
    }

    /// scoring.rs:62-64 — WEB-DL/WEBRip/BluRay/BDRip.
    static func isWebishSource(_ source: Source) -> Bool {
        switch source {
        case .webDl, .webRip, .bluRay, .bdRip: return true
        default: return false
        }
    }

    // MARK: - Private helpers

    /// scoring.rs:66-70 — any active-debrid slug flagged cached.
    static func isCachedOnActive(_ parsed: ParsedStream, _ active: [String]) -> Bool {
        active.contains { slug in parsed.cached[slug] == true }
    }

    /// scoring.rs:201-207.
    static func isTracked(_ s: ParsedStream, _ opts: ScoreOptions) -> Bool {
        isCachedOnActive(s, opts.activeDebrids)
            || s.stream.url != nil
            || (s.seeders.map { $0 >= trackingMinSeeders } ?? false)
    }

    // MARK: Date parsing (scoring.rs:72-196 — Rust chrono_parse + days_from_civil)

    /// Parses the ISO shapes the engine sees in practice: full internet datetime
    /// (with optional fractional seconds and offset, `T` or space separator) and
    /// date-only `yyyy-MM-dd` (UTC midnight, matching Rust `days_from_civil * 86_400_000`).
    /// Returns milliseconds since the Unix epoch, or nil when unparsable.
    static func parseISODateToMs(_ s: String) -> Double? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let d = isoFractionalFormatter.date(from: trimmed) ?? isoStandardFormatter.date(from: trimmed) {
            return d.timeIntervalSince1970 * 1000.0
        }
        if let d = dateOnlyFormatter.date(from: trimmed) {
            return d.timeIntervalSince1970 * 1000.0
        }
        if let d = dateTimeTFormatter.date(from: trimmed) {
            return d.timeIntervalSince1970 * 1000.0
        }
        if let d = dateTimeSpaceFormatter.date(from: trimmed) {
            return d.timeIntervalSince1970 * 1000.0
        }
        return nil
    }

    private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoStandardFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dateTimeTFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    private static let dateTimeSpaceFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// scoring.rs:184-190.
    static func currentTimeMs() -> Double {
        Date().timeIntervalSince1970 * 1000.0
    }

    /// scoring.rs:192-196.
    static func daysSince(_ releaseDate: String?) -> Double? {
        guard let date = releaseDate, let ms = parseISODateToMs(date) else { return nil }
        return (currentTimeMs() - ms) / 86_400_000.0
    }

    // MARK: Reason builders

    /// scoring.rs:262-305 — signal label is the resolution label ("4K", "1080p", …).
    static func resolutionReason(_ r: Resolution) -> ScoreReason {
        ScoreReason(signal: r.rawValue, delta: resolutionPoints(r))
    }

    /// scoring.rs:272-280.
    static func hdrLabel(_ h: HdrFormat) -> String {
        switch h {
        case .hdr10: return "HDR10"
        case .hdr10Plus: return "HDR10+"
        case .dv: return "DV"
        case .dvHdr10: return "DV+HDR10"
        case .hlg: return "HLG"
        }
    }

    /// scoring.rs:307-330 — Atmos +3, TrueHD/DTS-HD MA +2, DD+ +1, else 0 (not emitted).
    static func audioPoints(_ audio: AudioInfo) -> ScoreReason {
        switch audio.codec {
        case .atmos: return ScoreReason(signal: "Atmos", delta: 3.0)
        case .trueHD: return ScoreReason(signal: "TrueHD", delta: 2.0)
        case .dtsHdMa: return ScoreReason(signal: "DTS-HD MA", delta: 2.0)
        case .ddPlus: return ScoreReason(signal: "DD+", delta: 1.0)
        default: return ScoreReason(signal: "audio", delta: 0.0)
        }
    }

    /// scoring.rs:332-350 — strong (+8) before trusted (+4), else 0 (not emitted).
    static func trustedAddonPoints(_ parsed: ParsedStream) -> ScoreReason {
        let name = parsed.stream.addonName
        if regexMatches(strongAddonRegex, name) {
            return ScoreReason(signal: "strong-addon", delta: 8.0)
        }
        if regexMatches(trustedAddonRegex, name) {
            return ScoreReason(signal: "trusted-addon", delta: 4.0)
        }
        return ScoreReason(signal: "addon-neutral", delta: 0.0)
    }

    /// scoring.rs:355-369 — max(0, 12 − 4p).
    static func addonPriorityPoints(_ parsed: ParsedStream) -> ScoreReason {
        guard let p = parsed.stream.addonPriority else {
            return ScoreReason(signal: "addon-priority-none", delta: 0.0)
        }
        let delta = max(0.0, addonPriorityMax - Double(p) * addonPriorityStep)
        return ScoreReason(signal: "addon-priority-\(p)", delta: delta)
    }

    // MARK: Penalty helpers

    /// scoring.rs:371-391 — DTS/DTS-HD MA −6; TrueHD −4; mkv + (DTS|TrueHD) −3;
    /// avi/wmv −8; AV1 −2. All stack; emitted as one `webview2-unfriendly` reason.
    static func playabilityPenalty(_ parsed: ParsedStream) -> Double {
        var penalty = 0.0
        if parsed.audio.codec == .dts || parsed.audio.codec == .dtsHdMa {
            penalty -= 6.0
        }
        if parsed.audio.codec == .trueHD {
            penalty -= 4.0
        }
        if parsed.container == .mkv && (parsed.audio.codec == .dts || parsed.audio.codec == .trueHD) {
            penalty -= 3.0
        }
        if parsed.container == .avi || parsed.container == .wmv {
            penalty -= 8.0
        }
        if parsed.codec == .av1 {
            penalty -= 2.0
        }
        return penalty
    }

    /// scoring.rs:421-455 — CAM markers in name/title/filename/description while the
    /// parsed source is not theater and resolution is 1080p/4K: −200 (4K) / −100 (1080p).
    static func camInFilenamePenalty(_ s: ParsedStream) -> Double {
        if isTheaterSource(s.source) { return 0.0 }
        guard s.resolution == .p1080 || s.resolution == .uhd else { return 0.0 }

        var parts: [String] = []
        if let n = s.stream.name { parts.append(n) }
        if let t = s.stream.title { parts.append(t) }
        if let hints = s.stream.behaviorHints {
            if let f = hints.filename { parts.append(f) }
            if let fn = hints.fileName { parts.append(fn) }
        }
        if let d = s.stream.description { parts.append(d) }
        let haystack = parts.joined(separator: " \n ")

        guard regexMatches(camMarkerRegex, haystack) else { return 0.0 }
        return s.resolution == .uhd ? -200.0 : -100.0
    }

    /// scoring.rs:457-469 — MB/min by resolution: 4K 60, 1080p 18, 720p 8, 480p 3, SD 2.
    static func expectedMinSizeBytes(_ resolution: Resolution, _ runtimeMin: Int) -> Double? {
        guard runtimeMin > 0 else { return nil }
        let mbPerMin: Double
        switch resolution {
        case .uhd: mbPerMin = 60.0
        case .p1080: mbPerMin = 18.0
        case .p720: mbPerMin = 8.0
        case .p480: mbPerMin = 3.0
        case .sd: mbPerMin = 2.0
        }
        return mbPerMin * Double(runtimeMin) * 1024.0 * 1024.0
    }

    /// scoring.rs:471-501 — −120/−60/−20 when size/expected < 0.25/0.5/0.75.
    /// Exempt: theater sources and the lossy groups YTS/YIFY/YTSAG/YTS-AG.
    static func sizeMislabelPenalty(_ s: ParsedStream, _ expectedMin: Double?) -> Double {
        guard let sz = s.size, sz > 0, let expected = expectedMin else { return 0.0 }
        if isTheaterSource(s.source) { return 0.0 }
        if let group = s.releaseGroupNormalized, lossyTrustedGroups.contains(group.uppercased()) {
            return 0.0
        }
        let size = Double(sz)
        guard size < expected else { return 0.0 }
        let ratio = size / expected
        if ratio < 0.25 { return -120.0 }
        if ratio < 0.5 { return -60.0 }
        if ratio < 0.75 { return -20.0 }
        return 0.0
    }

    /// scoring.rs:503-573 — movie-only, days < 90, non-theater:
    /// 4K < 6 GiB −250; 1080p < 1.5 GiB −200; 720p < 0.6 GiB −80.
    static func undersizedNewReleasePenalty(_ s: ParsedStream, _ opts: ScoreOptions) -> ScoreReason {
        if opts.mediaKind == "series" {
            return ScoreReason(signal: "undersized-skip-series", delta: 0.0)
        }
        guard let date = opts.releaseDate else {
            return ScoreReason(signal: "undersized-skip-no-data", delta: 0.0)
        }
        guard let size = s.size else {
            return ScoreReason(signal: "undersized-skip-no-data", delta: 0.0)
        }
        guard let t = parseISODateToMs(date) else {
            return ScoreReason(signal: "undersized-skip-bad-date", delta: 0.0)
        }
        let days = (currentTimeMs() - t) / 86_400_000.0
        if days >= 90.0 {
            return ScoreReason(signal: "undersized-skip-mature", delta: 0.0)
        }
        if isTheaterSource(s.source) {
            return ScoreReason(signal: "undersized-skip-theater", delta: 0.0)
        }
        let sizeGB = Double(size) / 1_073_741_824.0
        if s.resolution == .uhd, sizeGB < 6.0 {
            return ScoreReason(signal: "4k-undersized-\(formatOne(sizeGB))gb", delta: -250.0)
        }
        if s.resolution == .p1080, sizeGB < 1.5 {
            return ScoreReason(signal: "1080p-undersized-\(formatOne(sizeGB))gb", delta: -200.0)
        }
        if s.resolution == .p720, sizeGB < 0.6 {
            return ScoreReason(signal: "720p-undersized-\(formatOne(sizeGB))gb", delta: -80.0)
        }
        return ScoreReason(signal: "undersized-ok", delta: 0.0)
    }

    /// scoring.rs:575-578 — one-decimal rounding (Rust `(x*10).round()/10` + `{:.1f}`).
    static func formatOne(_ x: Double) -> String {
        let rounded = (x * 10.0).rounded() / 10.0
        return String(format: "%.1f", rounded)
    }

    /// scoring.rs:580-633 — bandwidth budget:
    /// required > 1.1× budget → −45 (−120 if > 1.5×), softened +10 when cached;
    /// > 0.8× → −12; 4K under 25 Mbps −30/−60; 1080p under 8 Mbps −20/−45.
    static func bitrateBudgetPenalty(_ s: ParsedStream, _ opts: ScoreOptions, cached: Bool) -> ScoreReason {
        guard let budget = opts.bandwidthMbps, budget > 0.0 else {
            return ScoreReason(signal: "bitrate-ok", delta: 0.0)
        }
        let headroom = budget * 0.8

        if let size = s.size, let runtime = opts.runtimeMinutes, size > 0, runtime > 0 {
            let required = Double(size) * 8.0 / (Double(runtime) * 60.0) / 1_000_000.0
            if required > budget * 1.1 {
                let severity = required > budget * 1.5 ? -120.0 : -45.0
                return ScoreReason(
                    signal: "bitrate-exceeds-budget:\(Int(required.rounded()))>\(Int(budget.rounded()))Mbps",
                    delta: cached ? severity + 10.0 : severity
                )
            }
            if required > headroom {
                return ScoreReason(
                    signal: "bitrate-tight:\(Int(required.rounded()))/\(Int(budget.rounded()))Mbps",
                    delta: -12.0
                )
            }
        }
        if s.resolution == .uhd, budget < 25.0 {
            return ScoreReason(signal: "low-bandwidth-4k", delta: cached ? -30.0 : -60.0)
        }
        if s.resolution == .p1080, budget < 8.0 {
            return ScoreReason(signal: "low-bandwidth-1080p", delta: cached ? -20.0 : -45.0)
        }
        return ScoreReason(signal: "bitrate-ok", delta: 0.0)
    }

    /// scoring.rs:635-701 — movie-only, days < 90, non-theater:
    /// < 250 MiB → −250; < max(500 MiB, runtime×5 MiB/min) → −200.
    static func impossiblySmallMoviePenalty(_ s: ParsedStream, _ opts: ScoreOptions) -> ScoreReason {
        if opts.mediaKind == "series" {
            return ScoreReason(signal: "tiny-skip-series", delta: 0.0)
        }
        guard let size = s.size else {
            return ScoreReason(signal: "tiny-skip-no-size", delta: 0.0)
        }
        guard let date = opts.releaseDate else {
            return ScoreReason(signal: "tiny-skip-no-date", delta: 0.0)
        }
        guard let t = parseISODateToMs(date) else {
            return ScoreReason(signal: "tiny-skip-bad-date", delta: 0.0)
        }
        let days = (currentTimeMs() - t) / 86_400_000.0
        if days >= 90.0 {
            return ScoreReason(signal: "tiny-skip-mature", delta: 0.0)
        }
        if isTheaterSource(s.source) {
            return ScoreReason(signal: "tiny-skip-theater", delta: 0.0)
        }
        let sizeMB = Double(size) / (1024.0 * 1024.0)
        if sizeMB < 250.0 {
            return ScoreReason(signal: "new-release-virus-\(Int(sizeMB.rounded()))mb", delta: -250.0)
        }
        let runtimeFloor = opts.runtimeMinutes.map { Double($0) * 5.0 } ?? 0.0
        let floorMB = max(500.0, runtimeFloor)
        if sizeMB < floorMB {
            return ScoreReason(signal: "new-release-no-label-\(Int(sizeMB.rounded()))mb", delta: -200.0)
        }
        return ScoreReason(signal: "tiny-ok", delta: 0.0)
    }

    // MARK: Fresh theatrical adjust (scoring.rs:703-834)

    /// Preconditions: movie (mediaKind != "series"), release date parses, days < 150.
    /// Theater-dominated corpus = trustedTrackedCount ≥ 4 && theaterCaptureFraction ≥ 0.4
    /// && theaterCaptureFraction > webishFraction. If not dominated and days ≥ 30 → no-op.
    /// Deltas per docs/audit/stream-engine.md §4.1/§4.2 (fresh-theater-* / fresh-fake-*).
    static func freshTheatricalAdjust(
        _ s: ParsedStream,
        _ opts: ScoreOptions,
        hasValidSize: Bool,
        corpus: CorpusStats
    ) -> ScoreReason {
        if opts.mediaKind == "series" {
            return ScoreReason(signal: "fresh-skip-series", delta: 0.0)
        }
        guard let date = opts.releaseDate else {
            return ScoreReason(signal: "fresh-skip-no-date", delta: 0.0)
        }
        guard let t = parseISODateToMs(date) else {
            return ScoreReason(signal: "fresh-skip-bad-date", delta: 0.0)
        }
        let days = (currentTimeMs() - t) / 86_400_000.0
        if days >= theaterWindowDays {
            return ScoreReason(signal: "fresh-skip-mature", delta: 0.0)
        }

        let isTheaterCapture = isTheaterSource(s.source)
        let isRemuxOrBluray = s.source == .bluRay || s.remux
        let claimsHighQuality = s.source == .webDl || s.source == .webRip
            || isRemuxOrBluray
            || s.resolution == .p1080 || s.resolution == .uhd

        let theaterDominated = corpus.trustedTrackedCount >= 4
            && corpus.theaterCaptureFraction >= 0.4
            && corpus.theaterCaptureFraction > corpus.webishFraction

        if !theaterDominated && days >= shortFreshDays {
            return ScoreReason(signal: "fresh-skip-mature", delta: 0.0)
        }

        if isTheaterCapture {
            if theaterDominated {
                let sourceOffset: Double
                switch s.source {
                case .cam: sourceOffset = 95.0
                case .ts, .hdts: sourceOffset = 75.0
                default: sourceOffset = 65.0
                }
                return ScoreReason(signal: "fresh-theater-cinema-window", delta: sourceOffset)
            }
            if days < 14.0 {
                return ScoreReason(signal: "fresh-theater-mild-boost", delta: 25.0)
            }
            return ScoreReason(signal: "fresh-theater-neutral", delta: 0.0)
        }

        if !claimsHighQuality {
            return ScoreReason(signal: "fresh-low-quality-noise", delta: 0.0)
        }

        if theaterDominated {
            if isRemuxOrBluray {
                return ScoreReason(signal: "fresh-fake-remux", delta: -200.0)
            }
            if days < 0.0 {
                return ScoreReason(signal: "fresh-fake-prerelease", delta: -160.0)
            }
            if days < 14.0 {
                return ScoreReason(signal: "fresh-fake-prebluray", delta: -90.0)
            }
            return ScoreReason(signal: "fresh-fake-soft", delta: -45.0)
        }

        if isRemuxOrBluray && days < 14.0 {
            return ScoreReason(signal: "fresh-prebluray-suspect", delta: -55.0)
        }
        if days < 0.0 && !hasValidSize {
            return ScoreReason(signal: "fresh-prerelease-soft", delta: -35.0)
        }
        return ScoreReason(signal: "fresh-soft-flag", delta: -10.0)
    }

    /// Substring regex test (case-insensitive where the pattern declares it).
    static func regexMatches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text)) != nil
    }
}
