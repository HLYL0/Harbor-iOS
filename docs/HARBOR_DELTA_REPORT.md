# Harbor Delta Report

> Continuously compares the iOS project against current Harbor `main`.
> Refresh before each major development milestone (spec §103). Update this file whenever Harbor ships a release or merges a parity-relevant PR.

## Baseline

| Field | Value |
|---|---|
| Baseline Harbor commit | `0117755` (2026-09-02 audit) |
| Baseline Harbor version | 0.9.21 |
| iOS project | HLYL0/Harbor-iOS, SwiftUI + MPVKit, iOS 17 |
| Last delta check | 2026-09-02 |

## Delta log

### 2026-09-02 — initial baseline (no deltas yet)

- Audited current main. No drift to port (baseline established).
- Open PRs that will change parity when merged — watch list:

| PR | Watch reason |
|---|---|
| #950 Flutter mobile client | Harbor's own iOS/iPadOS client — treat as authoritative behavior reference for mobile UX once it lands |
| #965 Harbor Sync | E2E-encrypted cross-device sync — new subsystem to evaluate for iOS (Keychain-scoped, iCloud-capable) |
| #1028 player queue + Still Watching | player feature surface |
| #1032 ASS normalization | subtitle pipeline |
| #1045 background download manager | downloads on iOS = background-session design |
| #1017 manga/mobile/remote port | new content rooms |
| #1192 size parse separators | stream parser rule change (parity test vector!) |

## Procedure (each milestone)

1. `git fetch` the Harbor reference clone; note HEAD.
2. Diff the module map: new files, deleted files, renamed modules.
3. For each relevant change: port behavior → update parity matrix row → add/update test vector → note in this file.
4. New release (tag) → full re-run of `docs/audit/` reports where the subsystem changed.

## Current delta status

**NONE** — baseline just established.
