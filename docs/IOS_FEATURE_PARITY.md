# IOS Feature Parity Matrix

> Master matrix (spec §10). One row per user-visible Harbor feature area.
> Status vocabulary: DISCOVERED / PLANNED / IN DEVELOPMENT / IMPLEMENTED / TESTING / PASS / PARTIAL / BLOCKED / IOS NATIVE EQUIVALENT / DISTRIBUTION RESTRICTED.
> **Nothing reaches PASS without evidence** (CI green + on-device confirmation + test artifacts). Behavior detail lives in `docs/audit/*.md`; update this file whenever an audit or milestone changes a row.

## A. Rooms & navigation

| Feature | Harbor Source | Current Harbor Behavior | iOS Strategy | Status | Tests | Evidence | Known Limitation | App Store |
|---|---|---|---|---|---|---|---|---|
| Home (rotating hero, rails, Top 10, Continue Watching, personalized rails, row order) | `views/home.tsx`, `views/rooms/*` | see `audit/rooms-ui.md` | SwiftUI Home w/ hero pager + rail carousels; row-order from settings | PLANNED | — | — | row customization parity is settings-dependent | SAFE |
| Discover (personalization, Critics Pick, Discovery Queue, swipe) | `lib/discover/*` | see `audit/rooms-ui.md` | SwiftUI swipe/queue UI + same scoring inputs | PLANNED | — | — | personalization data is device-local | SAFE |
| Movies (CinemaHero, Top 10, trending, theaters, mood, decades…) | `views/rooms/movies*` | see `audit/rooms-ui.md` | native rails | PLANNED | — | — | — | SAFE |
| Shows (airing, networks, K-drama, British TV, seasons/episodes, next-episode) | `views/rooms/shows*` | see `audit/rooms-ui.md` | native rails + episode date validation (no unaired playback) | PLANNED | — | — | — | SAFE |
| Anime (Kitsu/AniZip/TMDB/MAL pipeline, awards, dub/sub) | `providers/anime-*`, `lib/anilist` | see `audit/metadata-anime.md` | first-class Anime room + mapping pipeline port | PLANNED | — | — | — | SAFE |
| Live TV (M3U/Xtream/XMLTV, categories, favorites, catch-up) | `lib/iptv/*` | see `audit/live-tv-dvr.md` | portable parsers + native EPG timeline | PLANNED | — | — | — | REVIEW RISK |
| Calendar (TMDB/Library/Trakt/sources, month view) | `views/calendar*` | see `audit/rooms-ui.md` | SwiftUI month calendar + source filters | PLANNED | — | — | — | SAFE |
| My Library (watchlist, history, progress, Trakt repair) | `views/library*` | see `audit/rooms-ui.md` | native library + progress sync | PARTIAL | — | — | MVP has none | SAFE |
| Addons room (installed/browse/community store, detail, config) | `views/settings/addons.tsx` | see `audit/stremio-addons.md` | native addon manager + discovery | PARTIAL | unit tests exist | MVP: install/remove/sync only | — | REVIEW RISK |
| Settings | `views/settings/*` | see `audit/rooms-ui.md` | native settings | PARTIAL | — | MVP: auth + debrid key | — | SAFE |
| Detail (poster/backdrop/logo/ratings/providers/cast/awards/streams/subs) | `views/detail.tsx` | see `audit/rooms-ui.md` | native detail + source picker | PARTIAL | VM tests exist | MVP: metadata + streams | — | SAFE |
| Person / Award pages | `views/person*`, `lib/awards` | see `audit/rooms-ui.md` | native person + award pages | PLANNED | — | — | — | SAFE |
| Search (global, debounce, suggestions, history) | `components/search/*` | see `audit/rooms-ui.md` | `.searchable` + debounce + cancel | PARTIAL | — | MVP: catalog search | — | SAFE |
| Profiles (per-profile settings, PIN) | `settings/profile-store.ts` | see `audit/sync-storage.md` | native profiles + hashed PIN | PLANNED | — | — | — | SAFE |
| Player (full-screen, HUD editor, gestures) | `views/player.tsx`, `components/player/*` | see `audit/player.md` | MPVBackend player + native gestures | PARTIAL | — | MVP: play/pause/seek/sub track | HUD editor later | SAFE |
| Next Up | `views/next-up*` | see `audit/rooms-ui.md` | native rail/queue | PLANNED | — | — | — | SAFE |
| Theme Studio | `views/theme-studio*` | see `audit/themes-i18n.md` | native editor, sandboxed custom code | PLANNED | — | — | custom JS restricted | RISK→RESTRICTED (JS) |
| Diagnostics | `views/diagnostics*` | — | native diagnostics screen | PLANNED | — | — | — | SAFE |
| Backup/Restore (.harbx) | `lib/*backup*` | see `audit/sync-storage.md` | portable format, no secrets | PLANNED | — | — | — | SAFE |
| Watch Together | `lib/together/*` | see `audit/casting-together.md` | room client + relay | PLANNED | — | — | relay external | SAFE |
| Manga / remote / wrapped (beta PRs) | PR #1017 etc. | not yet in main | DELTA WATCH — do not build until merged | DISCOVERED | — | — | — | — |

## B. Stream engine

| Feature | Harbor Source | iOS Strategy | Status | Tests | Evidence |
|---|---|---|---|---|---|
| Parse (resolution/HDR/codec/audio/source/container/…) | `harbor-core/src/parser.rs` + TS parser | Swift port of Rust core, golden-vector verified | PLANNED | Rust tests on Windows + vector parity on CI | — |
| Trust (fake/CAM/mismatch/year/season/episode/size…) | `harbor-core/src/trust.rs` | same port | PLANNED | vectors | — |
| Score + rank (corpus, weights, debrid priority, prefer AAC) | `harbor-core/src/scoring.rs` | same port incl. corpus stats | PLANNED | vectors | — |
| Debrid cache check / library | `pipeline.ts` + `lib/debrid/*` | RD flow exists; extend to AllDebrid/Premiumize/Debrid-Link/TorBox | PARTIAL | RD resolver tests exist | MVP RD only |
| Resolve/validate (size gates, HEAD probe, preflight) | `resolve.ts`, `preflight.ts` | port gates + URLSession probe | PLANNED | — | — |
| Episode file matching / season packs | `episode-file.ts`, PR #1119 | port matching rules | PLANNED | vectors | — |
| Custom stream filters | `custom-filters.ts` | native filter UI | PLANNED | — | — |

## C. Player & media

| Feature | Harbor Source | iOS Strategy | Status | Tests | Evidence |
|---|---|---|---|---|---|
| libmpv playback (MKV/AVI/DASH/headers/soft subs) | `mpv.rs` + `lib/player/mpv.ts` | MPVKit (built, on device) | TESTING | compile+link CI | MVP IPA verified |
| AVPlayer fallback (HLS/MP4/PiP) | `lib/player/html5/*` | AVPlayerBackend | PARTIAL | — | MVP has AVPlayer path |
| Retry / stall / freeze detection | `mpv-failure.ts`, `playback-clock.ts` | port state machine | PLANNED | — | — |
| Stream switching / fallback | `stream-switch-guard` test | native picker + auto-fallback | PLANNED | — | — |
| Resume / watched threshold / progress | `playback-history`, `saveResumeMs` | native progress store | PARTIAL | — | — |
| Auto-next / previous | player bridge | native queue | PLANNED | — | — |
| Skip intro/outro/recap (AniSkip/TheIntroDB/chapters) | `lib/skip-intro/*` | port providers | PLANNED | — | — |
| Subtitles (SRT/VTT/ASS/SUB, dual, style, delay, sync) | `lib/player/sub*`, `subsync/` | MPV sub pipeline + Rust subsync port | PARTIAL | — | MVP: basic subs |
| Speed / A-B loop / sleep timer | `lib/player/*` | mpv props | PLANNED | — | — |
| PiP / AirPlay / Now Playing | `pip.rs` (desktop) | system APIs | PLANNED | — | UNKNOWN for libmpv PiP |
| Trickplay scrubbing previews | `thumbs.rs` | AVAssetImageGenerator + cache | PLANNED | — | — |
| Player HUD editor (drag controls) | `components/player/*` | SwiftUI drag-drop editor | PLANNED | — | — |
| Statistics overlay | player transport | mpv stats overlay | PLANNED | — | — |
| Multiview (1–4 tiles) | `multiview.rs` | device-aware tiles | PLANNED | — | — |
| Anime4K | `anime4k.rs` | mpv user-shaders | PLANNED | — | — |
| Motion interpolation / SVP | `svp.rs` | NOT APPLICABLE on iOS | BLOCKED | — | documented |
| RTX HDR | `rtx-hdr.rs` | NOT APPLICABLE | BLOCKED | — | documented |

## D. Stremio & sync

| Feature | Harbor Source | iOS Strategy | Status | Tests | Evidence |
|---|---|---|---|---|---|
| Stremio login/session/logout | `auth.tsx` | Keychain session (exists) | TESTING | — | MVP verified |
| Addon collection sync + local install | `lib/addons-store/*` | exists | TESTING | unit tests | MVP verified |
| Addon discovery store (community) | `components/addons/*` | native discovery UI | PLANNED | — | — |
| Trakt (auth/sync/watchlist/history/ratings/reco/calendar/up-next) | `lib/trakt/*` | native adapters | PLANNED | — | — |
| Simkl / AniList / MAL | `lib/simkl`, `lib/anilist`, `lib/mal` | native adapters | PLANNED | — | — |
| Debrid: RD + AllDebrid + Premiumize + Debrid-Link + TorBox | `lib/debrid/*` | multi-service resolver | PARTIAL | RD tests | MVP RD only |
| Harbor Sync (E2E-encrypted) | PR #965 | DELTA WATCH | DISCOVERED | — | — |
| Notifications (Discord webhook, Telegram) | `lib/discord/*` | URLSession POST adapters | PLANNED | — | — |
| Discord Rich Presence | `discord_rp.rs` | NOT APPLICABLE → Now Playing | BLOCKED | — | documented |

## E. Local media & storage

| Feature | Harbor Source | iOS Strategy | Status | Tests | Evidence |
|---|---|---|---|---|---|
| Local library / folders | `local_lib.rs` | Files picker + security-scoped bookmarks | PLANNED | — | — |
| Downloads + background manager | `download.rs` | URLSession background transfers | PLANNED | — | — |
| Built-in torrent engine | `torrent_engine/*` | BLOCKED (background) → debrid path | BLOCKED | — | documented |
| DVR | `dvr.rs` | foreground recording only | BLOCKED (partial) | — | honest docs |
| Theme presets + custom themes | `lib/theme.ts` | token system port | PARTIAL | — | MVP: Harbor theme |
| i18n (all languages, RTL/Arabic first-class) | `lib/i18n/*`, `lib/arabic/*` | Localizable + RTL | PARTIAL | — | Arabic UI exists |

## F. Platform integrations

| Feature | Harbor Source | iOS Strategy | Status | Tests | Evidence |
|---|---|---|---|---|---|
| Casting: Chromecast/DLNA/Roku | `cast*.rs`, `dlna.rs`, `roku.rs` | CastingManager adapters | PLANNED | — | investigate after player |
| AirPlay | `airplay.rs` (server) | system sender routes | PLANNED | — | — |
| Watch Together + relay | `together/*`, `cf_relay.rs` | room client; relay external | PLANNED | — | — |
| Deep links (stremio:// harbor://) | plugin-deep-link | CFBundleURLTypes + validation | PLANNED | — | — |
| Privacy blocker (WebView) | `lib/privacy/*` | WKContentRuleList (only where WKWebView used) | PLANNED | — | — |
| Song identification | `song_id.rs` | ShazamKit | PLANNED | — | — |

## G. Cross-cutting

| Feature | Status | Notes |
|---|---|---|
| Performance budgets (startup, scroll, playback start, memory) | PLANNED | `IOS_PERFORMANCE.md` |
| Accessibility (VoiceOver, Dynamic Type, Reduce Motion) | PLANNED | `IOS_TEST_PLAN.md` |
| Arabic/RTL testing suite | PLANNED | spec §98 mandatory |
| Chaos/failure injection | PLANNED | spec §96 |
| Windows CI leg (structural + portable tests) | PLANNED | spec §91 |
| Cloud iOS CI (test→build→IPA→verify) | TESTING | existing pipeline, green |

---

## Status summary

- TESTING: 4 · PARTIAL: 9 · PLANNED: ~40 · BLOCKED: 5 · DISCOVERED: 3 (delta-watch)
- PASS: **0** — nothing is PASS until parity evidence exists.
