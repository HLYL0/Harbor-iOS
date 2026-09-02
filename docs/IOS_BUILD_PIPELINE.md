# IOS Build Pipeline

> The automated cloud iOS build. **The developer never operates macOS.** `git push` is the only trigger.

## Overview

```
Windows (developer)
   │  git push
   ▼
GitHub Actions — macos-15 runner
   │  install xcodegen (brew, tap-trust flags)
   │  xcodegen generate          → HarborIOS.xcodeproj from project.yml
   │  xcodebuild build (generic/platform=iOS, CODE_SIGNING_ALLOWED=NO)
   │  xcodebuild test (simulator, unit tests)
   │  strip _CodeSignature / embedded.mobileprovision
   │  fake-sign (jailbroken path — application-identifier entitlement)
   │  package IPA (Python zipfile, Payload/ root, ZIP_STORED)
   │  verify bundle Info.plist + CodeResources
   │  upload artifact
   ▼
Developer downloads artifact on Windows
   │  → Filza (LO's Dopamine device) or AltStore/Sideloadly
   ▼
iPhone
```

## Runner & toolchain

- `runs-on: macos-15` — Xcode 16.x. (`macos-14` is deprecated and unsupported after Nov 2, 2026 — never use it for new work.)
- XcodeGen emits project format 77 — fine on Xcode 16.
- `SWIFT_VERSION: "5.0"` (Xcode 16 accepts only 4.0/4.2/5.0/6.0 language modes; `"5.9"` is fatal).
- Homebrew needs `HOMEBREW_NO_REQUIRE_TAP_TRUST=1` and `HOMEBREW_NO_AUTO_UPDATE=1` before `brew install xcodegen`.

## Build matrix

| Build | Signing | Target | Purpose |
|---|---|---|---|
| Windows dev build | none (no compile) | n/a | structural verification only |
| Windows test build | none | Python/Rust portable tests | pre-CI gating |
| iOS cloud dev build | unsigned | generic/platform=iOS | CI artifact for AltStore/Sideloadly |
| iOS cloud jailbroken build | fake-signed (ad-hoc + application-identifier) | generic/platform=iOS | Filza install on LO's Dopamine device |
| iOS release / App Store build | **not implemented** — requires paid Apple Developer identity | App Store Connect | documented, not automated |

Differences: the jailbroken build adds the fake-sign step (entitlements: `application-identifier`, `com.apple.developer.team-identifier`, `get-task-allow`, `platform-application`) after the signature strip. The sideload build ships stripped-unsigned (AltStore applies the user's Apple ID signature). Both come from the same `xcodebuild` output; only post-processing differs.

## Key invariants baked into the workflow

1. `_CodeSignature` + `embedded.mobileprovision` stripped before packaging.
2. IPA packaged by Python `zipfile` (never raw `zip`/`ditto` for the archive) with `Payload/<App>.app/...` paths and `ZIP_STORED`.
3. Bundle verification step: extract artifact, parse `Payload/Harbor.app/Info.plist`, assert required keys (`LSRequiresIPhoneOS`, `UIRequiredDeviceCapabilities=[arm64,metal]`, `UIRequiresFullScreen`, `UILaunchStoryboardName`, `UIUserInterfaceStyle=Dark`), assert `_CodeSignature/CodeResources` exists (jailbroken path).
4. `TEST_HOST`/`BUNDLE_LOADER` pinned to `$(BUILT_PRODUCTS_DIR)/Harbor.app/Harbor` because `PRODUCT_NAME: Harbor` ≠ target name `HarborIOS` (Pitfall: "Could not find test host").
5. Unit tests run on the simulator leg before the device build — compile/logic failures fail the run before any artifact is produced.

## MPVKit (libmpv) integration

- SPM package `NuvioMedia/MPVKit`, branch `Nuvio`, resolved in `project.yml` `packages:`.
- Brings libmpv + MoltenVK: MKV/AVI/WebM/DASH/soft subs/header-protected sources.
- Expected IPA size growth is significant (tens of MB) — accepted for capability parity; see `IOS_PLAYER_ARCHITECTURE.md`.

## Failure triage

1. Download the failing run log.
2. `python scripts/extract_xcode_errors.py build.log` — buckets error classes, largest first.
3. Fix the class, re-push. Repeat until 0 errors. Never claim "will work now" — the CI run is the verdict.

## Artifacts

| Artifact | Contents |
|---|---|
| `Harbor-iOS-unsigned-ipa.zip` | `HarborIOS.ipa` (unsigned or fake-signed per matrix row) |
| build logs | full xcodebuild output |

## TestFlight / App Store (future)

Requires LO's Apple Developer Program membership and distribution signing. Automation path: fastlane `match` + App Store Connect API keys (secrets held by LO, never by the agent). Documented in `IOS_APPSTORE.md`; intentionally **not** part of the current pipeline.
