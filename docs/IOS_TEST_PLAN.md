# IOS Test Plan

> Test strategy per spec §93–98. Windows-run tests are canonical where possible; macOS CI adds Swift/device truth. Nothing is claimed tested without its artifact.

## Test tiers

| Tier | Where | Scope |
|---|---|---|
| T0 — Rust reference | Windows (`cargo test` in `rust/harbor-core`) | parser/trust/scoring golden vectors — the parity anchor |
| T1 — Portable logic | Windows (Python runners in `scripts/parity/`) | M3U/XMLTV/Xtream, subtitle timing, URL validation, backup format — run against both Rust reference and recorded Swift outputs |
| T2 — Swift unit | macOS CI (simulator) | DTOs, addon registry, persistence, stream-engine port vs vectors, view models |
| T3 — Swift integration | macOS CI (simulator, network-mocked) | Stremio/addon flows, debrid, Trakt, EPG, themes, backup round-trip |
| T4 — On-device | LO's iPhone (manual + reported) | playback matrix, HDR, PiP, gestures, lifecycle, memory |

## Unit test inventory (target)

| Subsystem | Cases |
|---|---|
| Stream parsing | every signal: resolution/HDR10/DV/HLG/codecs/audio/channels/source/container/size/seeders/group/edition/anime CRC/batch/cache — from Rust test vectors |
| Trust | fake/CAM/TS/TC/trailer/extra/wrong year/season/episode/size/mismatch — every rejection rule + rescue re-admission |
| Scoring/ranking | corpus stats, weights, debrid priority, prefer-AAC, addon order — identical ordering on golden fixture sets |
| Anime mapping | Kitsu→AniZip→TMDB chains, episode file matching, season packs, dub/sub detection |
| Addons | manifest schema, resource routing, install/remove/reorder, malformed manifests, config UI parsing |
| Metadata | provider response mapping, award badge derivation, ratings normalization |
| EPG/M3U/Xtream | parsing, catch-up URL transforms (default/append/shift/flussonic/xtream), VOD classification |
| Subtitles | SRT/VTT/ASS/SUB parsing, time shift, dual-track selection, style presets |
| Themes | preset parsing, custom theme import validation, token resolution |
| Backup | .harbx round-trip, secret exclusion, schema versioning, malformed import rejection |
| Player state | resume/threshold, auto-next, stall/freeze state machine, stream-switch guard |
| Deep links | stremio:// harbor:// parsing, allowlist, rejection of malformed input |
| Profiles/PIN | profile isolation, PIN hashing, parental gating |

## Integration test inventory (target)

| Flow | Mock strategy |
|---|---|
| Stremio login → addon sync → browse → metadata → streams → play | recorded fixtures + live smoke (Cinemeta) |
| Debrid resolve (each service) | recorded API fixtures per provider |
| Trakt/Simkl/MAL/AniList auth + sync | recorded OAuth fixtures |
| Live TV: add playlist → EPG → catch-up playback | fixture playlists + EPG XML |
| Watch Together: create/join/seek sync | local relay stub |
| Local media: pick file → play → resume | simulator fixture files |

## Parity harness (spec §43)

`scripts/parity/stream_vectors.py`:
1. Extracts test vectors from `rust/harbor-core` tests (they are the canonical inputs).
2. Runs the Rust core on Windows → records expected parse/trust/score/rank.
3. CI runs the Swift port against the same vector JSON → diff must be empty or every difference justified in `IOS_KNOWN_LIMITATIONS.md`.

## Chaos & fuzz (spec §96)

- Malformed: addon JSON, manifest, M3U, XMLTV, SRT/VTT/ASS, .harbx, deep links → NO CRASH, NO CORRUPTION, NO SECRET LEAK, NO HANG.
- Failure injection: timeouts, 500s, rate limits, network drop mid-stream, storage full, memory pressure.
- Run in T1/T2; every crash becomes a regression test.

## RTL / Arabic (spec §98, mandatory)

- Arabic UI + Arabic metadata + Arabic subtitles (rendered, shaped), mixed RTL/LTR, Arabic numerals, dates, times, player controls.
- T2 snapshot-ish checks where possible; visual confirmation on-device.

## Device matrix (spec §97)

| Device | Status |
|---|---|
| iPhone 15 Pro (LO's — jailbroken, iOS 17.3.1) | available — primary |
| Mid-range / older iPhone | **not available** — documented gap |

## Regression against Harbor (spec §99)

Each Harbor release/merge: delta report → affected rows → port → update vectors → update this plan. The `HARBOR_DELTA_REPORT.md` procedure is authoritative.
