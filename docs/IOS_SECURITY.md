# IOS Security

> Threat model and hardening baseline for Harbor-iOS (spec §87). Maintained alongside implementation; every subsystem lands with its row checked.

## Assets

| Asset | Storage | Rule |
|---|---|---|
| Stremio auth key | Keychain, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | never logged, never in backups dirs |
| Debrid API keys | Keychain (same class) | redacted in diagnostics |
| Trakt/Simkl/MAL/AniList tokens | Keychain | OAuth tokens never in file storage |
| Settings/themes/addon list | app storage, versioned | no secrets |
| Playback progress/library | app storage + sync services | conflict-resolved, not randomly overwritten |
| PINs | hashed (never plaintext) | per profile |

## Threat model (top vectors)

| Vector | Mitigation |
|---|---|
| Malicious addon manifests / responses | schema validation, size caps, timeout+backoff, no code execution from addon data |
| Malicious media URLs | scheme allowlist (https for playback; http blocked at verifier level), URL validation before player |
| Malformed subtitles (SRT/VTT/ASS/SUB) | parse into internal model, cap size, reject binary garbage |
| Custom theme code (CSS/JS) | **sandboxed renderer only; no native bridge exposure**; disabled by default in restricted builds; CSS-only first, JS behind explicit opt-in and capability allowlist |
| Deep links (harbor:// stremio://) | validate against registry; no arbitrary navigation; no scheme-triggered network auth |
| Backup/restore (.harbx) | **no secrets exported**; import validates schema + caps size; optional passphrase |
| WebView usage | only where a feature truly needs it; JavaScript off by default; no persistent cookies shared with the app session |
| Rust FFI / native bridge | only the vendored harbor-core crate (pure logic) is eligible; no arbitrary code |
| Local network (casting/watch-together) | local-network permission + user-initiated discovery only; TLS where feasible |
| Logs | structured + redacted; no tokens, keys, or full URLs w/ query secrets |

## App transport & sandbox

- ATS: arbitrary HTTP loads **forbidden** (verifier enforces). Media exceptions only per-URL, never global.
- Sandbox: no entitlements beyond what features need (local network only when casting lands; background audio only for player).
- No executable execution, no shell, no `Process` usage. All parsing is in-process, bounded, cancellation-aware.

## Supply chain

- SPM deps pinned by revision (MPVKit branch `Nuvio`). Any new dependency: license check + `THIRD_PARTY_LICENSES.md` row + pinned version.
- CI secrets: none. Repo permissions read-only in workflow.
- Artifact integrity: IPA structure + plist + entitlement verification in CI (already enforced).

## Verification

- Chaos/fuzz: malformed addon JSON, M3U/XMLTV, subtitle files, deep links, backup files → NO CRASH, NO CORRUPTION, NO SECRET LEAK, NO HANG (spec §96).
- Security findings gate release: a failing row blocks the milestone.
