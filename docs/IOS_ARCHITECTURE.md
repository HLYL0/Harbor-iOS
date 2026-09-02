# IOS Architecture

> Canonical architecture for Harbor-iOS. Every implementation, subagent, and PR must follow this document.
> Subsystems that disagree with this document must propose a change here FIRST, never silently fork the architecture (spec §3).

## 1. Decision records

### DR-001: Native SwiftUI (chosen)

**Context.** Harbor Desktop = React 19 + Tauri 2 + libmpv (Rust process). Options for iPhone: SwiftUI native, React Native, Expo, Capacitor/WebView, Tauri Mobile (2.x alpha), Flutter, WebView-wrap of desktop UI.

**Decision.** SwiftUI + UIKit where needed (libmpv via MPVKit).

**Why.**
- A WebView-wrap of the desktop UI is explicitly forbidden by the spec (§12) and fails mobile UX standards.
- React Native/Expo/Capacitor: buildable from Windows, but the player requirement (MKV, ASS subs, DASH, header-auth, HDR, soft subs, debrid flows) pushes any non-native stack into custom native modules anyway — at which point SwiftUI is less total surface, not more.
- Tauri Mobile: iOS support is alpha-stage; toolchain risk is unacceptable for a parity target this large.
- Flutter: Harbor upstream is itself building a Flutter mobile client (PR #950). Technically viable, but (a) it would discard the verified working Swift/MPVKit/RD-resolver foundation already installed on LO's device, (b) LO's established tooling, skills, and CI are Swift/XcodeGen, (c) no evidence Flutter + libmpv embedding beats SwiftUI + MPVKit for our constraints.
- SwiftUI + XcodeGen + macOS CI is the **only stack in this project that has already produced a working IPA on LO's device** (libmpv playback verified).

**Consequences.** macOS-CI remains the Apple build backend. Windows stays the authoring/test environment. Flutter PR #950 becomes a *behavior reference* for mobile UX parity, not our stack.

### DR-002: Player = libmpv (MPVKit) primary, AVPlayer fallback

**Decision.** Player abstraction with two backends:

```
PlayerEngine (protocol: load/play/pause/seek/audio/subtitles/…)
 ├── MPVBackend   (NuvioMedia/MPVKit — libmpv + MoltenVK; default)
 └── AVPlayerBackend (HLS/MP4 fallback + system PiP/AirPlay fidelity)
```

**Why.** Harbor's entire desktop playback model is libmpv (same family): subtitle styling, track switching, MKV/ASS, resumable state, speed, A/B loop, hw decode (VideoToolbox) — porting behavior onto AVPlayer would be a rewrite of most of it. AVPlayer remains for cases where system integration wins (PiP/AirPlay on protected HLS) and as a degraded-mode fallback. Selection logic lives in one place (see `IOS_PLAYER_ARCHITECTURE.md`).

### DR-003: Stream engine = Rust reference + Swift port, golden-vector parity

**Decision.** `harbor-core` (pure Rust: parser/trust/scoring/types — no Tauri deps) is the canonical logic:
1. Vendored as a Rust crate in-repo (MIT attribution) → `cargo test` runs on **Windows** = canonical test vectors.
2. Swift port (`Domain/StreamEngine`) validated on CI against those same vectors: parse → trust → score → rank must be identical or explicitly justified.
3. Optional endgame: compile `harbor-core` to `aarch64-apple-ios` staticlib on the macOS runner (Xcode SDK is present there) and FFI-link it for byte-exact parity — the crate's `cdylib/rlib` crate-types already allow it. The only obstacle is wasm-bindgen gating (`cfg` split); deferred until the Swift port proves insufficient.

**Why.** Exact ranking parity is the single most user-visible Harbor behavior. A hand-translated port drifts; a shared Rust core cannot drift.

### DR-004: Cross-platform logic stays cross-platform

Rust and Python carry the Windows-testable logic: stream engine, EPG/M3U/Xtream parsers, subtitle parsing, URL validation, backup format, theme model. Swift owns: UI, lifecycle, platform services, and thin protocol adapters. Anything testable on Windows must be tested on Windows (spec §15).

## 2. Layered architecture

```
iOS UI (SwiftUI, mobile-first — never shrunk desktop UI)
   │
Presentation (Features/* views + view models, navigation, sheets)
   │
Application Services (AppEnvironment, session/profile, addon registry,
   │                  sync orchestrators, player coordinator)
Domain Core (models, use-cases, StreamEngine, catalogs, EPG, themes)
   │
  ├── Stremio Ecosystem        ├── Media System
  │    AddonClient             │    PlayerEngine (MPV|AVPlayer)
  │    Catalog/Metadata        │    Subtitles, skip-intro, trickplay
  │    Account/Session         │    CastingManager (AirPlay/…)
  │    Library/Progress        │    PiP/AudioSession
   │
Platform Adapters (URLSession, Keychain, SQLite/JSON stores,
   │               Rust bridge if enabled, MPVKit, Metal)
   │
macOS CI build (XcodeGen + xcodebuild + MPVKit SPM)
```

Rules:
- Features may depend on Domain; never Domain on Features.
- `Core/DesignSystem` may depend on Apple frameworks only.
- No view model imports SwiftData/network directly — repositories/services only (existing contract, keep).
- External state (addons, sessions, keys) always through the service layer with cancellation + backoff.

## 3. Canonical interfaces (subagents MUST build on these, not invent)

| Concern | Canonical home |
|---|---|
| Stremio DTOs | `Domain/Models/StremioModels.swift` (extend, don't fork) |
| Addon registry/persistence | `AddonPersistenceState` + `AddonPersistence` (existing) |
| Session/keys | `KeychainStore` (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) |
| Networking | URLSession wrapper w/ timeout/retry/backoff/cancel → `Domain/Networking/` |
| Player | `PlayerEngine` protocol → `MPVBackend`, `AVPlayerBackend` |
| Stream engine | Rust crate `rust/harbor-core` (reference) + `Domain/StreamEngine/` (Swift port) |
| Storage | versioned JSON stores per concern; SQLite only where Harbor needs relational (library progress) |
| Errors | typed `LocalizedError` enums per subsystem; redacted diagnostics |

## 4. iOS module map (target layout)

```
HarborIOS/          entry, AppEnvironment, RootView (tab bar), resources
Core/
  DesignSystem/     theme tokens, components (ScreenContainer, cards, rails…)
Data/
  Stremio/          StremioAPIClient (+ addon client)
  Debrid/           RealDebridClient (+ more services per parity)
  Persistence/      KeychainStore, stores (settings, library, themes, EPG cache)
  Sync/             Trakt/Simkl/MAL/AniList adapters
  LiveTV/           M3U/XMLTV/Xtream parsers (portable, golden-tested)
Domain/
  Models/           DTOs
  StreamEngine/     parser/trust/scoring/ranking (Swift port of harbor-core)
  Networking/       HTTP client, caching
  Services/         protocols (StremioServicing, PlayerEngine, …)
Features/
  Home/ Discover/ Movies/ Shows/ Anime/ LiveTV/ Calendar/ Library/ Addons/
  Settings/ Search/ Details/ Person/ Player/ WatchTogether/ Themes/
rust/
  harbor-core/      vendored reference crate (cargo test on Windows)
scripts/            verification, parity test runners (Windows-runnable)
docs/               this document set
```

## 5. Windows-testable core (spec §14–15)

Runs on the developer PC, no macOS:

- `rust/harbor-core` → `cargo test` (parse/trust/score/rank)
- `scripts/parity/` → Python runners executing golden vectors (stream ranking, M3U/XMLTV/EPG, subtitle timing, URL validation, backup format) against both Rust reference and recorded Swift outputs
- structural gates: `scripts/verify_project.py`

CI (macos-15) adds: Swift unit tests, simulator integration tests, device build, IPA. **Windows never claims to validate what only CI can** (spec §16).

## 6. Error & logging model

- Typed errors per subsystem; user-facing strings localized (Arabic first-class).
- Structured diagnostic log (in-app screen): app/OS versions, player backend, sanitized errors — never secrets (spec §70).
- Network failures follow: timeout → retry w/ exponential backoff → partial results → graceful UI.

## 7. Change control

- New subsystem → proposal to this doc + parity matrix row + test plan first.
- Harbor delta (spec §103): before each milestone, refresh the reference clone and run the delta procedure in `HARBOR_DELTA_REPORT.md`.
- Subagents: one canonical architecture (this doc). Parallel tracks may challenge it; they may not silently fork it.
