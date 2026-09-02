import Foundation

// MARK: - Stream ranking. Mirror of `harbor-core/src/scoring.rs` rank_and_pick (Rust truth,
// scoring.rs:1255-1304). The spec (docs/audit/stream-engine.md §4.7) pins ranking parity to
// the RUST semantics, not the TS `scoring-rank.ts` variant:
//
//   - TS pre-sorts by score desc when respectAddonOrder is false; Rust does NOT — it only
//     applies the stable cached-first sort. We mirror Rust.
//   - Rust counts ANY `url` as cached (TS additionally requires !hasUncachedMarker). We mirror Rust.
//   - Rust EXCLUDES theater sources (CAM/TS/HDTS/TC) from `primary`; TS does not. We mirror Rust.
//   - `preferAac` exists only in TS and is intentionally absent here.

/// Deterministic port of Harbor's Rust `rank_and_pick`.
enum Ranking {

    /// scoring.rs:1255-1304 — rank and pick, mirroring Rust exactly:
    ///
    /// 1. Optional pre-sort (`respectAddonOrder`): addonPriority asc → addonReturnIdx asc →
    ///    score desc; missing values = Int.max (Rust u32::MAX). Rust `slice::sort_by` is
    ///    STABLE, so equal keys keep their input order (mirrored via index tiebreak).
    /// 2. Stable cached-first sort: cached = `url` present OR any active-debrid slug true.
    ///    Not cached → keeps previous relative order.
    /// 3. `byTier`: FIRST stream per tier in cached-first order; keys are tier rawValues
    ///    ("4K_DV", "4K_HDR", "4K", "1080p_HDR", "1080p", "720p", "SD", "ROUGH"). Rust
    ///    stores these in a BTreeMap, which serializes keys lexicographically — the Swift
    ///    dictionary is rebuilt with sorted keys so JSON output stays byte-identical.
    /// 4. `primary`: respectAddonOrder → first cached NON-THEATER stream; otherwise the
    ///    highest-scored cached non-theater (Rust Iterator::max_by — LAST maximum wins on
    ///    ties). Fallback: first non-theater overall; final fallback: first overall.
    static func rankAndPick(scored: [ScoredStream], opts: ScoreOptions) -> RankedPicker {
        let active = opts.activeDebrids
        var cachedFirst = scored

        // scoring.rs:1261-1271 — addon-order pre-sort (stable in Rust).
        if opts.respectAddonOrder {
            cachedFirst = cachedFirst.enumerated().sorted { a, b in
                let priorityA = a.element.parsed.stream.addonPriority ?? Int.max
                let priorityB = b.element.parsed.stream.addonPriority ?? Int.max
                if priorityA != priorityB { return priorityA < priorityB }
                let returnA = a.element.parsed.stream.addonReturnIdx ?? Int.max
                let returnB = b.element.parsed.stream.addonReturnIdx ?? Int.max
                if returnA != returnB { return returnA < returnB }
                if a.element.score != b.element.score { return a.element.score > b.element.score }
                return a.offset < b.offset
            }.map { $0.element }
        }

        // scoring.rs:1272-1276 — stable cached-first sort.
        cachedFirst = cachedFirst.enumerated().sorted { a, b in
            let cachedA = isCachedScored(a.element, active: active) ? 1 : 0
            let cachedB = isCachedScored(b.element, active: active) ? 1 : 0
            if cachedA != cachedB { return cachedA > cachedB }
            return a.offset < b.offset
        }.map { $0.element }

        // scoring.rs:1278-1282 — first stream per tier; BTreeMap key order = lexicographic.
        var byTierMap: [String: ScoredStream] = [:]
        for s in cachedFirst {
            let key = s.tier.rawValue
            if byTierMap[key] == nil { byTierMap[key] = s }
        }
        var byTier: [String: ScoredStream] = [:]
        for key in byTierMap.keys.sorted() { byTier[key] = byTierMap[key] }

        // scoring.rs:1284-1293 — cached NON-THEATER candidates.
        let cachedNonTheater = cachedFirst.filter {
            isCachedScored($0, active: active) && !Scoring.isTheaterSource($0.parsed.source)
        }

        let picked: ScoredStream?
        if opts.respectAddonOrder {
            picked = cachedNonTheater.first
        } else {
            // Rust Iterator::max_by keeps the LAST maximum on ties.
            picked = cachedNonTheater.reduce(nil as ScoredStream?) { best, s in
                guard let b = best else { return s }
                return s.score >= b.score ? s : b
            }
        }

        // scoring.rs:1294-1297 — fallbacks.
        let primary = picked
            ?? cachedFirst.first { !Scoring.isTheaterSource($0.parsed.source) }
            ?? cachedFirst.first

        return RankedPicker(primary: primary, byTier: byTier, all: cachedFirst)
    }

    /// scoring.rs:1248-1253 — `url` present OR any active-debrid slug cached (any url counts;
    /// TS's hasUncachedMarker exclusion does not exist in the Rust contract).
    private static func isCachedScored(_ s: ScoredStream, active: [String]) -> Bool {
        s.parsed.stream.url != nil
            || active.contains { slug in s.parsed.cached[slug] == true }
    }
}
