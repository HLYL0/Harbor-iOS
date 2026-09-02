# rust/harbor-core — vendored reference

Vendored from `harborstremio/harbor` (`harbor-core/`), MIT licensed, commit `0117755` (2026-09-02).

## Purpose

This crate is the **canonical** Harbor stream logic (parse → trust → score → rank). It runs on Windows via `cargo test` and produces the golden vectors that the Swift port (`Domain/StreamEngine/`) must reproduce exactly (see `docs/IOS_ARCHITECTURE.md` DR-003, `docs/IOS_TEST_PLAN.md`).

## Usage

```bash
cargo test          # Windows — runs the 56 canonical Rust tests
```

## Rules

- Do not modify upstream logic in this directory. If a bug exists here, it is Harbor's behavior — parity means reproducing it, not fixing it. Fixes belong upstream (PR to harborstremio/harbor) and get re-vendored.
- The only permitted local edits: `cfg` gating for non-wasm targets (wasm-bindgen) to allow native tests / future iOS staticlib builds.
- Re-vendor procedure: copy from the reference clone at the current audit commit; record the new commit in `docs/HARBOR_DELTA_REPORT.md` and here.

## License

MIT — see Harbor's LICENSE and `docs/THIRD_PARTY_LICENSES.md`.

---

# rust/vector-extractor — golden-vector generator

Replays the 56 `#[test]` scenarios of `harbor-core` (`parser.rs`, `trust.rs`, `scoring.rs`) through the REAL core functions and emits Swift-decodable golden JSON for parity testing.

## Run

```bash
# Windows git-bash; prepend the GNU toolchain (see repo tooling notes)
export PATH="$HOME/.cargo/bin:$PATH"
export PATH="/c/Users/Admin/AppData/Local/Microsoft/WinGet/Packages/BrechtSanders.WinLibs.POSIX.UCRT_Microsoft.Winget.Source_8wekyb3d8bbwe/mingw64/bin:$PATH"
cd rust/vector-extractor && cargo run
# Override the output path: STREAM_VECTORS_OUT=/path/to/file.json cargo run
```

Writes `Tests/Fixtures/stream-engine-vectors.json` (76 fixtures: parser 8, trust 26, scoring 34, corpus 3, ranking 5; 1 scenario skipped — see below).

## JSON layout

- `generator` — `harbor-core@<version>`.
- `parser[]` — `{label, stream (raw EngineStream), asserts, expected (ParsedStream)}`. Swift: parse `stream`, compare full `ParsedStream` equality.
- `trust[]` — `{label, streams (raw EngineStream[]), patches, options (TrustOptions), kept (ParsedStream[]), rejected ({stream, reason}[])}`. `patches` is an array per input stream of `{path, set}` post-parse overrides (camelCase paths over the Swift-shaped `ParsedStream`, e.g. `"size"`, `"scamScore"`, `"stream.infoHash"`, `"stream.extra.nzbUrl"`); the extractor applies them with `apply_patch()` after `parser::parse_stream` and before `trust::apply_trust` — mirroring how the Rust tests mutate their `base_stream()`. Swift replay: parse → patch → trust → compare kept/rejected.
- `scoring[]` — `{label, parsed (ParsedStream), options (ScoreOptions), corpus (CorpusStats input), expected ({score, tier, reasons})}`. Swift replay: run `scoreStream` and compare. Note zero-delta reasons (e.g. `fresh-skip-*`) are never recorded — matching `score_stream`'s non-zero-only `reasons` list.
- `corpus[]` — `{label, parsed (ParsedStream[]), options, expected (CorpusStats + rust-only percentiles `medianSize/p90Size/p10Seeders/p90Seeders`)}` for the three `compute_corpus_stats` tests. Swift's `CorpusStats` ignores the extra keys; decode with a wider model to assert them.
- `ranking[]` — `{label, scored (ScoredStream[]), activeDebrids, respectAddonOrder, expected ({primaryIndex, byTier: {tierKey: inputIndex}, order: [inputIndex...]})}`. Indices refer to positions in `scored` (streams have no ids); map by decoded-value equality.
- `skipped[]` — scenarios not expressible through the public API.

**Shape caveat:** the Rust types serialize FLAT (`#[serde(flatten)]`), but `EngineModels.swift` decodes the NESTED `{"stream": {...}}` / `{"parsed": {...}}` shape, so the extractor builds the JSON manually in the Swift shape. Do not switch it to derived serialization.

**Time-relative dates:** trust/scoring tests compute ISO dates relative to *now* (e.g. release 7 or 50 days ago). Options in those fixtures carry both the concrete `releaseDate` and `releaseDateDaysAgo`; a Swift harness must re-derive `releaseDate` from `releaseDateDaysAgo` at replay time (as the Rust tests do), otherwise the cinema/fresh windows drift out of range over time.

## Skipped

- `tokenize_decomposes_precomposed_accents` — exercises the private `trust::tokenize()` directly; not reachable via `apply_trust`. (The related private `title_matches("Rocky","Rocky II",1979,1976)` test IS re-expressed via `apply_trust` with `expectedTitle="Rocky"`, `expectedYear=1976`, stream `year=1979`, label `trust/title_year_tolerance_scales_with_age`.)

## Rules

Same as `harbor-core`: never modify upstream logic; this crate only ADDS fixtures. Regenerate the vectors after re-vendoring and diff.
