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
