# IOS Local Files & Downloads

> Local media + downloads design (spec §31, §74). iOS-native equivalents for desktop mechanisms; capability profiles per spec §74.

## 1. Local media (iOS-native equivalent)

Harbor desktop scans local folders (`local_lib.rs`). iOS has no arbitrary filesystem:

| Harbor | iOS |
|---|---|
| folder scanning | **Files app document picker** + `securityScopedBookmarks` for persistent folder access; on-demand indexing |
| metadata extraction | AVFoundation metadata + (optional) TMDB lookup by filename |
| thumbnails | AVAssetImageGenerator, bounded cache |
| subtitles | sidecar detection (.srt/.vtt/.ass) + subtitle search pipeline |
| resume/history | unified progress store (same as streamed content) |

## 2. Downloads

- **Technical capability**: URLSession download tasks (foreground + background transfer service). Resume via HTTP Range (same `.part` semantics as Harbor, but managed by URLSession). Debrid downloads = fetch unrestrict link → local file.
- **Capability profiles** (spec §74):
  - FULL/SIDELOAD: debrid + direct-URL downloads, Files-app-visible storage.
  - APP STORE SAFE: same technical path; distribution policy decides which sources are offered.
- No auto-resume after restart for interrupted items (Harbor parity — FACT: status `interrupted`); URLSession background tasks give us restart-resume for free on eligible items (documented safe improvement).

## 3. Debrid library as "downloaded" content

Port Harbor's `listLibrary()` per provider (RD `/torrents?limit=100&page=1..5` downloaded-only, TorBox mylist, etc.) as a "My Debrid Library" rail — playable via unrestrict, which IS the iOS-native replacement for the desktop torrent engine.

## 4. Backup / Restore (.harbx) — documented divergence (spec §32)

- Format parity for import: read Harbor's `{format:"harbor-backup", version:1, data:{harbor.*}, bgImage}` (plain JSON).
- **Export divergence (mandated by spec): iOS `.harbx` never contains secrets.** Harbor exports every API key and refresh token (FACT). iOS export includes: settings, profiles (PIN hashes only, no plaintext), themes, addon config; **excludes** all Keychain items (auth keys, debrid keys, sync tokens, Xtream credentials). A note in the export flow tells the user which credentials must be re-entered (or optionally exports a Keychain-only encrypted blob behind Face ID — Phase 20 decision).
- Restore: schema-capped import, size caps, validation before apply, wipe-portable-then-apply (same semantics, minus secrets).

## 5. Storage layout (iOS)

| Concern | Location |
|---|---|
| secrets (Stremio/debrid/Trakt/Simkl/MAL/AniList/Xtream) | Keychain (never app storage) |
| settings + profiles + themes + addon list | versioned JSON in Application Support (per-profile partition) |
| caches (images, metadata, EPG, trickplay) | Caches/ (bounded, purgeable, pressure-aware) |
| downloads + recordings | Documents/Harbor Downloads, Documents/Harbor DVR (Files-visible) |
| backup exports | user-chosen destination via share sheet / document picker |

Settings migration model: port Harbor's one-shot presence-flag migrations (per-profile blobs + shared/fork semantics); iOS adds a numeric schema version (safe improvement).
