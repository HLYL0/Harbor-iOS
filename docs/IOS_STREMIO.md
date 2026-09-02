# IOS Stremio

> Stremio account + protocol layer design. Behavior source: `docs/audit/stremio-addons.md` (verified). Existing MVP already covers most of this — this doc upgrades it to full parity.

## 1. Auth (parity + iOS-native mechanism)

| Harbor | iOS |
|---|---|
| Web login at stremio.com/login → auth key via **loopback HTTP callback** (`stremio_auth.rs`), 5-min timeout | `ASWebAuthenticationSession` with loopback callback capture (same flow, system browser sheet, Keychain for the key) |
| Auth key stored plaintext in localStorage per profile | **Keychain**, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (already in MVP — deliberate improvement, documented) |
| Sign-out is local-only (server endpoint defined but unused) | parity: local-only sign-out |

Email/password login (MVP path) stays as a secondary flow (Stremio's own API, already verified).

## 2. Protocol layer

- Base: `https://api.strem.io/api` — `login`, `logout`, `addonCollectionGet`, `addonCollectionSet`, `datastoreGet/Set` (for library/progress sync).
- Addon collection: per-account addon list; local copies slimmed (manifest-stripped persistence); local installs degrade to local-only when sync fails.
- Per-profile isolation: profiles map to Stremio user id/email (MVP's `stremio-id:`/`stremio-email:` pattern — keep).

## 3. Resource requests (exact behavior to port)

| Resource | Timeout | Notes |
|---|---|---|
| streams | 8s/22s per-addon (8s non-cached, 22s cached tiers), parallel, no retry, per-addon abort | progressive partial results; per-addon dedupe; Chrome-UA; `addonRanked` only for aiostreams |
| catalogs | 8s parallel | required-extra first-option resolution; `skip=` pagination; `search=` for search catalogs |
| metadata | Cinemeta-first race (4s addon timeout) | addon meta merges over Cinemeta |
| subtitles | `<id>:<s>:<e>` + `videoHash/videoSize/filename` extras | 30s safeFetch ceiling (known worst-case) |

Error policy: per-addon try/catch + allSettled; failures logged and dropped; **partial results always delivered** (spec §37).

## 4. Persistence

- Addon registry: `AddonPersistenceState` (exists) — extend with per-profile versioning + migration.
- Progress/library sync: Stremio datastore endpoints when authenticated (MVP lacks progress sync — Phase 8).
- Keychain items: auth key, debrid keys, Trakt/Simkl/MAL/AniList tokens, Xtream credentials (never in app storage).

## 5. Deep links (spec §71)

- Register `stremio://` and `harbor://` (CFBundleURLTypes) + validate every incoming URL (allowlist routes: `detail/<type>/<id>[/<videoId>]`, manifest.json installs, watch-party invites).
- Setting `stremioDeeplinkInstall` default **true** (parity).
- No arbitrary navigation from schemes; no scheme-triggered network auth.
