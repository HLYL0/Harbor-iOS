# Harbor — LIVE TV / IPTV / EPG / DVR / SPORTS — Forensic Audit

**Target:** Harbor v0.9.21 (Tauri 2 · React · TypeScript · Rust · libmpv) — Stremio client with a full IPTV subsystem.
**Repo inspected:** `C:/Users/Admin/AppData/Local/Temp/harbor-ref`
**Scope:** `src/lib/iptv/*` (all 38 files), `src/lib/dvr/*`, `src/lib/sports/*`, `src/lib/feed/*` (purpose only), `src-tauri/src/dvr.rs`, `src-tauri/src/lib.rs` (command registration), `src/views/live/**`, `src/views/live/guide/**`, `src/components/player/dvr-modal/**`, `src/components/player/live-channel-dvr.tsx`, `src/views/player/live-layer.tsx`, `src/chrome/recording-pill.tsx`, `src/lib/settings/types.ts`.

---

## 1. Playlist Support

### 1.1 Source model & persistence
- Sources live inside the global settings object as `iptvPlaylists: Array<{id, name, url, epgUrl?, kind?: "m3u"|"xtream"|"epg", xtream?: {server, username, password}}>` — `src/lib/settings/types.ts:442-453`, default `[]` (`src/lib/settings/defaults.ts:387`). Settings are serialized to `localStorage` key `harbor.settings` (read directly by `src/lib/iptv/settings-bridge.ts`).
- Playlist ids are `pl-{Date.now()}-{rand}` (`use-playlist-mutations.ts:46`).

### 1.2 Add / Edit / Delete / Refresh / Export (`src/views/live/hooks/use-playlist-mutations.ts`, `src/views/live/source-picker.tsx`)
- **Add:** form (3 kinds: M3U URL / Xtream / EPG) → `materializePlaylistEntry()` → appended to `settings.iptvPlaylists`; auto-activates unless EPG-only. Form validation: `http(s)` URL for m3u/epg; for Xtream: server must be `http(s)` + non-empty username/password (`playlist-form.tsx:59-69`). Xtream entries are stored **both** as structured `xtream: {server, username, password}` **and** as a baked `url` = `{server}/get.php?username=…&password=…&type=m3u_plus&output=ts` plus `epgUrl` = `{server}/xmltv.php?username=…&password=…` (`buildXtreamUrls`, `playlist-form.tsx:247-255`).
- **Edit:** replaces the entry, then `clearPlaylistCache(id)` + `deleteIptvCache("xtream-vod", id)` + `clearEpg(id)`; refreshes the active playlist (`use-playlist-mutations.ts:64-74`).
- **Delete:** removes entry, then `purgePlaylistState(id, …)` (`src/lib/iptv/source-cleanup.ts`) which wipes **all** derived state for that source: in-memory playlist cache, IndexedDB xtream-vod cache, EPG cache, channel stats, pins, group prefs, country prefs, EPG overrides, favorites.
- **Refresh:** a refresh button (`SourcePicker`, spinner + "Last updated {ago}") calls `useIptvPlaylist().refresh` → `loadPlaylist(src, {force:true})` (`use-iptv-playlist.ts:26`). There is also **automatic stale-while-revalidate**: `loadPlaylist` returns cached data and silently re-fetches in the background if the persistent cache is older than 6 h (`IPTV_CACHE_TTL_MS`, `persistent-cache.ts:3`; `store.ts:67-69`).
- **Reorder / move-to-top** of playlist entries: `reorderPlaylist(id, delta)` / `movePlaylistTop(id)`.
- **Export:** only for the active playlist — Tauri save dialog + `writeTextFile` with `buildM3u(playlist.channels, playlist.epgUrl)` (`use-live-actions.ts:76-93`). Suggested filename `{name}-{YYYY-MM-DD}.m3u` (`export.ts:48-52`).
- **Generated M3U** (`src/lib/iptv/export.ts:18-42`): `#EXTM3U url-tvg="…"` header when an EPG URL exists; per channel: `tvg-id`, `tvg-logo`, `group-title`, `catchup`/`catchup-source` (emitted when a catchup source exists), plus a passthrough whitelist of attrs (`tvg-name`, `tvg-chno`, `tvg-shift`, `tvg-language`, `tvg-country`, `duration`, `catchup-days`); duration `-1` default. Attr values are escaped (`"` → `\"`).
- **Generated EPG:** **does not exist.** The app never generates/edits XMLTV. EPG-only sources (`kind:"epg"`) are stored standalone and their URLs are auto-merged as fallback `extraUrls` for *every* playlist's EPG load (`live.tsx:104-108`). The form copy claims they are "kept for future attachment", but in practice they are attached to all playlists immediately.

### 1.3 M3U parsing rules (`src/lib/iptv/m3u.ts`, `parseM3u`)
- BOM strip; `\r?\n` split; `#EXTM3U` header ignored; unknown `#` lines ignored.
- Recognized directives: `#EXTINF`, `#EXTGRP` (sticky group — applies to the current pending entry and all subsequent entries lacking their own `group-title`), `#EXTVLCOPT`, `#KODIPROP`.
- **EXTINF attribute tokenizer** is quote-aware: whitespace-split tokens; first unquoted token = duration (seconds); `key=value` pairs lower-cased; quoted values may span multiple tokens (even-count quote closing detection); the title is the text after the first comma that follows the last closing quote (`attrTitleSplit`/`firstUnquotedComma`, `m3u.ts:131-152`).
- **EXTVLCOPT** captures only `http-user-agent` → `vlcopt-user-agent` and `http-referrer` → `vlcopt-referrer`.
- **URL-line pipe options** (`url|key=val&key2=val2`): `user-agent`, `referer|referrer`, `cookie` (captured only if not already set; URL-decoded).
- **KODIPROP** captures `inputstream.adaptive.license_type/key` → `kodiprop-license-type/key`.
- Channel id = `{baseId}::{tvg-id || tvg-name || title || "ch-N"}::{autoIndex}`; `tvgId` = `tvg-id` or `tvg-chno`; display name = `tvg-name` || title || `Channel N`; logo = `tvg-logo` || `logo`.
- **Decorative row filtering**: two layers — `isDecorativeRow` (symbol-only names, `m3u.ts:71-78`) drops rows at parse time; `isDividerChannel`/`filterChannelsForDisplay` (`divider-filter.ts`) drops ASCII/box-drawing divider rows (>55% symbol ratio) at display-shaping time (`shapePlaylist`, `store.ts:241-252`).
- `deriveEpgUrls(playlistUrl)` (`m3u.ts:211-232`): for `get.php`/`player_api.php` URLs with username/password, derives `{origin}/xmltv.php?username&password` and `{origin}/get.php?username&password&type=epg` (in that order).

### 1.4 Xtream Codes API (`src/lib/iptv/xtream.ts`)
- Credential parsing: only URLs whose path ends in `get.php` or `player_api.php` with `username`+`password` query params are treated as Xtream (`parseXtreamUrl`, `xtream.ts:16-28`). Structured creds via `credsFromServer(server, user, pass)` (strip trailing `/`, require scheme).
- All JSON calls go to `{base}/player_api.php?username=&password=&action=…` (`apiUrl`, `xtream.ts:121-129`). UA `IPTVSmartersPro/3.1.5`. Responses are parsed strictly: HTML/XML or invalid JSON → `XtreamAuthError` with a "account expired / not an Xtream server" message.
- **Account check** (`fetchXtreamUserInfo`, `xtream.ts:136-155`): `player_api.php?username&password` (no action) → `user_info.auth === 0` ⇒ auth failure; `status` `expired`/`banned`/`disabled` ⇒ typed errors; `allowed_output_formats` captured; `server_info.server_protocol === "https"` swaps the stream base to `https://{host}:{https_port}` (`deriveStreamBase`).
- **Live endpoints** (`fetchXtreamLiveChannels`, `xtream.ts:178-223`): parallel `get_live_categories` + `get_live_streams`; per stream: `tvgId = epg_channel_id`, group from category map, URL `{streamBase}/live/{user}/{pass}/{stream_id}.{ts|m3u8}`; container selected against `allowed_output_formats` (`pickContainer`, preference from setting `iptvLiveContainer`, default `ts`); `tv_archive > 0` ⇒ `attrs.catchup = "xtream"` + `catchup-days = tv_archive_duration`.
- **Short EPG** (`fetchXtreamShortEpg`, `xtream.ts:235-260`): `get_short_epg` with `{stream_id, limit: 8}` → `epg_listings[].{title, description, start_timestamp, stop_timestamp}`; titles/descriptions base64-decoded with a guarded decoder (charset regex, length%4, UTF-8 fatal, control-char rejection → falls back to raw).
- **VOD endpoints** (`xtream-vod.ts`): `get_vod_categories` + `get_vod_streams` → movie channels with URL `{base}/movie/{user}/{pass}/{id}.{ext}`, `attrs["tvg-type"]="movie"`.
- **Series endpoints**: `get_series_categories` + `get_series` → placeholder channels (`url:""`, `attrs["tvg-type"]="series"`, `attrs["xtream-series-id"]`); `get_series_info?series_id=…` → `episodes[seasonKey][]` → episode channels `S{season}E{ep}`, URL `{base}/series/{user}/{pass}/{episodeId}.{ext}` (`fetchXtreamSeriesEpisodes`, `xtream-vod.ts:142-181`). Series-info is cached in-memory per source (`seriesInfoCache`).
- Batch publishing of huge catalogs via `processInBatches` (256/batch, rAF yielding, early-stop via `onBatch` return false) (`xtream-batches.ts`; `catalog-publication-gate.ts` gates first paint of catalog updates).

### 1.5 XMLTV parsing (`src/lib/iptv/xmltv.ts`)
- **Streaming block parser**: no DOM — raw text is scanned for `<channel …` and `<programme` open tags; complete `</channel>`/`</programme>` blocks are parsed incrementally as chunks arrive; leftover buffer trimmed to the last 64 chars (there is a subtle reliance on attributes appearing before nested content — child tags are looked up by index, not nesting, which is safe for typical flat XMLTV).
- Hard limits: 200 MB payload; 30 s connect timeout; 25 s stall timer aborts; gzip sniffed from magic bytes `1f 8b` and inflated via `DecompressionStream("gzip")`; max 5 redirects; VLC 3.0.20 UA; Tauri HTTP plugin with `safeFetch` fallback for non-scoped URLs; progress callback fires ≥ every 3 s with new programs + channel meta.
- `parseProgramme`: requires `start`, `stop`, `channel` attrs; parses title (default `"Untitled"`), `desc`, `category`, `icon src`; drops programs with `end <= start`.
- `parseXmltvTime`: `YYYYMMDDHHMMSS` + optional `±HHMM` offset → epoch ms (UTC).
- `parseChannel`: `id`, `display-name`, `icon src` → `EpgChannelMeta`.
- Entity decoding (`&lt; &gt; &quot; &apos; &amp;`, hex/dec numeric) and CDATA unwrap.
- `indexProgramsByChannel` sorts per channel by `startMs`; `findCurrent` is a binary search returning `{current, next}`.

---

## 2. EPG Subsystem

### 2.1 Data model (`src/lib/iptv/types.ts`)
```
EpgProgram   { channelTvgId, title, description|null, startMs, endMs, category|null, iconUrl|null }
EpgChannelMeta { displayName|null, icon|null }
EpgIndex     { byChannel: Map<tvgId, EpgProgram[]>, channelMeta?, fetchedAt }
```

### 2.2 Store & loading (`epg-store.ts`)
- In-memory cache per playlistId with 1 h TTL; inflight dedupe; subscriber notification; **progressive indexing** — `onProgress` appends delta programs into a cloned per-channel map and re-sorts (live UX while a 200 MB file streams).
- Multi-URL fallback: first URL returning ≥1 program wins; empty results are skipped; if all fail but channel metadata was seen, an empty index + last-known `channelMeta` is returned (`doFetchWithFallback`, `epg-store.ts:91-121`).
- URL priority (`use-epg.ts:27-28`): playlist's own `epgUrl` OR derived Xtream URLs, then all EPG-only sources' URLs (`extraUrls`), deduped.

### 2.3 Channel ↔ EPG resolution (`epg-resolver.ts`)
1. **User override**: per-channel manual tvg-id mapping (`epg-map.ts`, localStorage `harbor.iptv.epgmap.v1`) wins.
2. Direct `channel.tvgId` lookup.
3. **Ambiguity guard**: if a tvg-id is shared by multiple channels (`computeTvgIdCounts`), programs are only shown when channel-name tokens match the normalized tvg-id tokens — otherwise rejected (prevents every "ESPN HD/SD/FHD" variant from showing identical wrong listings).
4. **Name fallback**: when no tvg-id matches, an index of normalized `display-name`s (Arabic-normalized via `rtl.ts`) is consulted.
5. **Time shift**: per-channel `tvg-shift` attr plus global setting `iptvEpgOffsetHours` (`settings-bridge.ts:21-24`) shift all program times.
- **Manual matching UI**: `EpgMatchModal` (`guide/epg-match-modal.tsx`) — pick a tvg-id from `epg.byChannel`/`channelMeta`, `setEpgOverride(channel.id, tvgId)`, with clear/undo.
- **Xtream fallback**: when the base EPG is empty, `useXtreamEpgFallback` hydrates `get_short_epg` for the first 120 channels (`xtream-short-epg.ts`, keyed by `tvgId || channel.id`).

### 2.4 EPG timeline UI (`src/views/live/guide/`)
- **Window**: fixed 8-hour grid (`WINDOW_HOURS = 8`), anchored to now — starts 1 h before now, aligned to 30-min slots (`startOfWindow`, `guide-utils.ts:9-13`); scale 5 px/min; channel column 200 px default, drag-resizable 140–560 px (persisted `harbor.guide.channel-col-px`); 76 px rows.
- **Time ruler** (`guide-time-ruler.tsx`): 30-min slots, hourly labels + day hints (Today / Tomorrow / Yesterday / weekday) — hints exist only because the 8-h window can cross midnight.
- **Now line**: red vertical line + "Now" pill; auto-scrolls so now sits ~1/3 from the left edge on first render (once, `scrolledRef` guard).
- **Program blocks** (`guide-program-block.tsx`): absolutely-positioned buttons; states: live (red border), past+replayable (accent border + "Replay" badge — shown only when `channelHasCatchup(ch)` AND an `onPlayCatchup` handler exists), past (dimmed "Ended"), future (normal). Click: replayable past program → catch-up URL playback; otherwise → live play. Hover/focus tooltip portal with title, start→end, duration, description (5-line clamp), category.
- **Date navigation: NOT IMPLEMENTED.** There is no control to move the window to yesterday/tomorrow/arbitrary days; the grid is always anchored to the current time. (FACT — the only "date" artifacts are ruler day hints.)
- Lazy channel virtualization (`useLazyVisible` sentinel), per-channel `content-visibility: auto`; stale channels capped with "Showing first N of M — use search" notice.
- EPG freshness tick: `useNowTick(30_000)`.

---

## 3. Catch-up (`src/lib/iptv/catchup.ts`)

### 3.1 Detection (`detectCatchupType`)
Type = `"default" | "append" | "shift" | "flussonic" | "xtream"`. Source of truth: `attrs["catchup"]` / `attrs["catchup-type"]` (lowercased), then `catchupSource`, then the URL shape:
- `flussonic` | `fs` → `flussonic`
- `xc` | `xtream` → `xtream`
- `append` → `append`
- `shift` | `timeshift` → `shift`
- `default` **or any `catchupSource` present** → `default`
- URL matching `XTREAM_LIVE_RX = /^(https?:\/\/[^/]+)\/(?:live\/)?([^/]+)\/([^/]+)\/(\d+)\.(\w+)(?:\?|$)/i` → `xtream` (auto-detection for Xtream live URLs, which is how `fetchXtreamLiveChannels` URLs become catch-up-capable even without the `catchup` attr).

### 3.2 Exact URL transformations (`buildCatchupUrl(ch, startMs, endMs, nowMs)`)
All times floored to seconds; `duration = max(60, end - start)`.

| Type | Transformation |
|---|---|
| **flussonic** | Match `^(.*)\/([^/]+)\.(m3u8|ts|mpd)$` on the URL **path**. If matched: `{dir}/{stem}-{start}-{duration}.{ext}{query}` where `stem` = filename except `mpegts`/`mono` → `index` (e.g. `…/channel.m3u8` → `…/channel-1756800000-3600.m3u8`). If no extension match: `{path}/archive-{start}-{duration}.ts{query}`. Query string preserved verbatim. |
| **xtream** | Regex the live URL to extract `host/user/pass/id`. Output: `{host}/timeshift/{user}/{pass}/{mins}/{Y-m-d:H-M}/{id}.ts` with `mins = ceil(duration/60)` and the timestamp = program **start** formatted `Y-m-d:H-M` (UTC), e.g. `…/timeshift/u/p/60/2026-09-02:14-30/1234.ts`. (Matches the well-known Xtream Codes `timeshift` convention.) |
| **catchupSource present** (any type incl. `default`, `append`, `shift` with a source) | If source is an absolute `http(s)` URL: template-fill the source itself. Else append to the channel URL with `?` or `&` (leading `?`/`&` stripped from the source). |
| **fallback** (`default` or `shift`/`append` with **no** catchupSource) | `{url}?utc={start}&lutc={now}` (classic Xtream `utc/lutc` shift). |

Template tokens (case-insensitive, `$` optional; `fillTemplate`, `catchup.ts:41-70`):
`${start}` `{start}` `{utc}` `{timestamp}`, `{end}` `{utcend}`, `{now}` `{lutc}` `{timenow}`, `{duration}` `{dur}`, `{offset}` (= `now − start`), `{duration-minutes}` (= `ceil(duration/60)`), plus strftime forms `${utc:FMT}`/`${start:FMT}`/`{utc:FMT}` with `Y m d H M S` (UTC, zero-padded).

### 3.3 Behavioral notes (FACT)
- `shift` and `append` have **no dedicated URL branches** — they flow into the generic `catchupSource` template-fill or the `?utc=&lutc=` fallback. The type only affects detection/UI gating (`channelHasCatchup`), not URL shape, except via the conventional semantics the fallbacks happen to match.
- `catchup-days` (from Xtream `tv_archive_duration`, or M3U `catchup-days` attr) is parsed and preserved but **never enforced** — no window/age validation when building catch-up URLs.
- Catch-up playback entry (`use-live-actions.ts:55-74`): `buildCatchupUrl` → `openPlayer({ url, title: program.title, subtitle: "{channel} · catch up", isLive: true, headers: headersFromChannel(ch) })`. If URL building fails, it silently falls back to live play.
- Playback headers (`channel-headers.ts`): `User-Agent` (vlcopt/http-user-agent), `Referer`, `Cookie` carried into the player for both live and catch-up.

---

## 4. DVR — What Is Actually Implemented (brutally honest)

### 4.1 REAL, fully wired

**Rust backend** (`src-tauri/src/dvr.rs`, commands registered at `src-tauri/src/lib.rs:730-734`):
- `dvr_start(args: {url, outputDir, filename, durationSec, channelName, programTitle?})`:
  - Locates a system `mpv` binary (`locate_mpv`, platform candidates: `mpv.exe`/`mpv` on Windows, homebrew paths on macOS, PATH search on Linux) — fails with `"mpv binary not found on system"`.
  - Creates the output dir; sanitizes the filename (invalid chars + control chars → `_`, fallback `"recording"`); output file is **always** `{dir}/{filename}.ts`.
  - Spawns **external mpv** as a headless recorder: `--no-terminal --quiet --idle=no --force-window=no --vo=null --ao=null --cache=yes --network-timeout=60 --user-agent="VLC/3.0.20 LibVLC/3.0.20" --stream-record={output} {url}`, stdin/stdout/stderr nulled, `kill_on_drop`, no console window on Windows.
  - Tracks the session in an in-memory `HashMap<uuid, ActiveRecording>`.
  - **Progress loop** (2 s tick): reads output-file size via `fs::metadata`, emits `dvr://progress` events `{id, outputPath, channelName, programTitle, startedAtMs, plannedDurationSec, bytesWritten, elapsedSec, state:"recording"}`; when `elapsed >= plannedDurationSec` → `finalize` (kills mpv, emits `dvr://done`).
  - **Watchdog loop** (2 s): polls `child.try_wait()`; on exit → `finalize` with `error = "mpv exited unexpectedly"` → `dvr://error`.
- `dvr_stop(id)` → `finalize` → `dvr://done`.
- `dvr_list()` → active sessions only (state `"recording"`).
- `dvr_default_dir()` → `{video_dir → download_dir → app_data_dir}/Harbor DVR` (auto-created).
- `dvr_reveal(path)` → opens the **parent** folder (`explorer`/`open`/`xdg-open`).

**Frontend**:
- `src/lib/dvr/provider.tsx` — React context; listens to `dvr://progress|done|error`; maintains `sessions` (active) + `terminal` (finished) lists; `start/stop/reveal/defaultDir/dismiss`.
- `src/components/player/dvr-modal/*` — record modal opened from the live player: duration choices derived from EPG (**current program until its end**, **current + next**, **just the next show**, or **custom 5–720 min**), output dir picker (remembers last dir in `harbor.dvr.lastDir`), filename prefilled `"{channel} - {program} (YYYY-MM-DD HHmm)"`, live progress view (bytes, elapsed bar, remaining, Stop, Show in folder).
- Trigger path: `src/views/player/live-layer.tsx` → `src/components/player/live-channel-dvr.tsx` (resolves the channel + current/next EPG programs) → `DvrModal`.
- `src/chrome/recording-pill.tsx` — player-chrome pill: pulsing **Rec** with % while recording, count badge for multiple concurrent sessions, dropdown listing active + finished sessions (Stop / Show / Dismiss).

### 4.2 REAL but shallow
- **Concurrency**: multiple simultaneous recordings work (each is its own mpv process).
- **Error surfacing**: mpv crash → "mpv exited unexpectedly" + file size captured.
- Finished sessions are listed in the UI only for the current app run (`dismiss` just removes the row).

### 4.3 STUB / NOT IMPLEMENTED (FACT)
- **No scheduled/future recordings.** The modal only records *now* (live URL) for a fixed duration. No timers, no EPG-driven scheduling, no "record the next show at 21:00".
- **No recording library.** There is no persistent list/history of recordings, no metadata browser, no poster/description enrichment, and **no in-app playback of recordings** (only "Show in folder"; the `.ts` is playable externally).
- **No persistence across restarts.** Session state is an in-memory Rust HashMap; app restart loses all sessions (files on disk remain, but the app has no index of them).
- **No disk-space checks.** No free-space validation before/during recording; a full disk surfaces as "mpv exited unexpectedly".
- **No settings page.** `src/views/settings/nav.tsx:4508-4511` only registers *search keywords* ("DVR / record", "record live tv", "r key") — there is no DVR settings section, no default-dir override UI, no quality settings.
- **No filename collision handling** — an existing `{filename}.ts` is silently overwritten by mpv.
- **No retry/resume** on network drop; no series/pass recording; no conflict management.
- **No catch-up/EPG-seek recording** — the modal records the *live* URL passed by `live-layer.tsx`, never a catch-up or timeshift URL.
- **Done-state UX quirk**: `ActiveView` can render a `done` session (shows "Recording finished" without Stop) because the modal matches sessions with `state === "recording" || "done"` for the same channel name.

---

## 5. Channel Categories / Favorites / Search / Logos / Pins

- **Categories (groups):** `group-title`/`#EXTGRP` for M3U, Xtream category names otherwise; `"Uncategorized"` bucket in `groupChannels`. Default ordering is relevance-scored: region first (score 100/80 from `REGION_TO_TOKENS`), then preferred UI languages (60 − 5·i), neutral bump for Entertainment/News/Sports/Movies/Kids/Documentary (`group-relevance.ts`). Per-source user prefs: pin/hide groups (`group-order.ts`, `applyUserGroupOrder` in `channel-order.ts`). Group logos = first channel logo in the group (`use-channel-pipeline.ts:142-146`).
- **Favorites** (`favorites.tsx`): localStorage `harbor.iptv.favorites.v2` (migrates legacy `v1` id-list); stores a snapshot `{id,name,logo,group,url,tvgId,sourceId}` so favorites survive even if the source is removed (stub sources with no URL are still resolved/played via any playlist with a matching source id, `live.tsx:190-200`); virtual `__FAVORITES__` group is the default landing group when non-empty; `hydrate()` backfills URLs for legacy entries; removed with the source.
- **Pins** (`pins.ts`): localStorage `harbor.iptv.pins.v1` — **ordered** list of channel ids; pinned channels surface first, then most-watched (≥ 3 plays), then the rest (`applyUserChannelOrder`, `channel-order.ts`). Per-source cleanup on delete.
- **Play stats** (`channel-stats.ts`): `harbor.iptv.stats.v1`, max 600 entries (pruned by recency); feeds "Most watched"/"Recent" ordering and `topChannels`.
- **Search:** text filter with Arabic-aware matching — normalized Arabic (harakat stripped, أإآٱ→ا, ة→ه, ى/ئ→ي, ؤ→و) for both haystack and needle (`rtl.ts`).
- **Logos:** `tvg-logo`/`logo`; channel cards fall back to an initial letter on error (`channel-card.tsx:92,108`); country flags via `https://flagcdn.com/w40/{code}.png` (`country-detect.ts:112-114`).
- **Country detection/filtering** (`country-detect.ts`, `country-prefs.ts`): group-name → flag-emoji decode or alias table (US/GB/…, SA/KSA, UAE, ARABIC, LATINO, EXYU, NORDIC…), `tvg-country` attr; per-source selected-country filtering; country prefixes stripped from group labels.
- **Channel hydration** (`channel-hydration.ts` + `channel-title.ts`): channel names (stripped of country prefixes, quality tokens, `SxxExx`, `24/7`, noise words) are searched on Cinemeta (`v3-cinemeta.strem.io`) to enrich movie-channel rows with real metadata; 7-day TTL, 5000-entry LRU; news/sports/radio/music/weather/events/deportes names are skipped.
- **Top networks** (`top-networks.ts`): curated regex rows of major US networks (Broadcast / News / Sports / Premium) rendered as a home row (`top-networks-rows.tsx`) — a discoverability layer over arbitrary playlists.

---

## 6. Sports & Feed Modules — Purpose

### 6.1 `src/lib/sports/espn.ts` (891 lines, single file)
A client for ESPN's public site API (`https://site.api.espn.com/apis/site/v2/sports`) powering the **live-scores rail on the Live TV home** (`live-home/sports/*`):
- `LEAGUES` list with Arabic/English labels, led by Saudi Pro League (ROSHN) then EPL, UCL, NBA, NFL, etc.; groups incl. soccer/basketball/combat(MMA); `DEFAULT_SPORTS_LEAGUES = ["ROSHN","EPL","UCL","NBA","NFL"]` (`espn.ts:345`).
- `fetchSports(leagues)` → parallel per-league scoreboards, in-memory cache + inflight dedupe (`fetchLeague`, ~line 560-604), `sortGames` (in-progress → pre → post), `liveCount`.
- `fetchMatchSummary(leagueTag, eventId)` → full detail: lineups/rosters (starters, subs, goals, cards, headshots), team stats (possession/shots/corners/fouls/cards), key events (goal/yellow/red/substitution), formations; **MMA special-case** — scoreboard-derived summary (ESPN's MMA summary endpoint is noted broken in-code) plus fighter profiles from `sports.core.api.espn.com/v2/sports/mma/leagues/ufc/athletes/{id}`.
- UI: `use-sports.ts` polls every 12 s while the tab is visible; `sports-card.tsx`, `sports-marquee.tsx`, `sports-hover-preview.tsx`, `sports-customize-modal.tsx`, `match-detail-view.tsx`.
- Purpose: scoreboard/companion layer *next to* IPTV sports channels — it is **not** a stream finder; no channel mapping exists between ESPN games and playlist channels.

### 6.2 `src/lib/feed/*` (29 files)
The home-**feed** content engine for the app's main (non-live) home screen: row assembly (`sections`, `pool`, `rank`, `daily-rows*`), personalization (`preferences`, `moods`, `genre-topics`, `genre-spotlights`, `award-winners`, `featured/*`), and filtering (`exclude`, `seen-ids`, `skipped`, `external-watched`, `locale`, `tags`, `themes`). **Not part of the IPTV/Live-TV subsystem** — included in scope only to confirm there is no live/EPG/DVR logic hiding there (there isn't).

---

## 7. Xtream Credential Storage (FACT)

- **Plaintext in localStorage**: settings key `harbor.settings` contains `iptvPlaylists[].xtream = {server, username, password}` **and** the derived `url` (`get.php?username=…&password=…&type=m3u_plus&output=ts`) — credentials are therefore stored twice, unencrypted (`use-playlist-mutations.ts:13-26`, `playlist-form.tsx:247-255`).
- **IndexedDB cache** (`persistent-cache.ts`, DB `harbor-iptv-cache`): cached playlists contain channel URLs of the form `/live/{username}/{password}/{id}.{ext}` — i.e., credentials embedded in every cached stream URL. The cache key includes an FNV-1a signature computed over the credentials (hash only; the values still contain them in cleartext URLs).
- No OS keychain/encryption/redaction anywhere in the IPTV path. Settings persistence itself (localStorage vs other mechanisms) is owned by `src/lib/settings`, out of scope here, but the IPTV bridge reads/writes the same `harbor.settings` key (`settings-bridge.ts`).
- Passwords are masked in the add/edit form (`type="password"`, `autoComplete="new-password"`) — UI-only masking.

---

## 8. FACT vs INFERENCE

### FACT (verified in code)
- Everything in sections 1–7 with a file path.
- DVR is **manual-start, fixed-duration, live-only**, via an external headless mpv `--stream-record` process; sessions are volatile; no scheduling, no library, no disk checks, no in-app playback of recordings.
- Catch-up supports exactly the five types listed, but `append`/`shift` have no dedicated URL logic; `catchup-days` is never enforced.
- The EPG guide has a fixed 8-hour now-anchored window; there is no date navigation.
- There is no EPG generation/export; only M3U export.
- Xtream credentials are stored in cleartext (localStorage + baked URLs + cached stream URLs).
- `dvr_*` commands are registered (`lib.rs:730-734`); the recording pill and modal are wired into the player chrome and live layer.

### INFERENCE (reasonable, not directly proven by code reads)
- The app presumably keeps recording files after restart (files exist on disk) but shows no trace of them — inferred from the absence of any index/library.
- "No date nav" and "no scheduling" are absence-based conclusions: they could conceivably exist in code paths not under the audited directories, but nothing in `src/views/live/**`, `src/lib/iptv/**`, `src/lib/dvr/**`, or `dvr.rs` references them.
- The `EpgMatchModal` "No EPG channels match" empty state implies EPG-only sources with no channel defs can leave the guide without listings.
- The DVR "done" session still appearing under the channel (until dismissed) is a UX byproduct of the modal matching `state === "recording" || "done"` by channel name.
- Feed (`src/lib/feed/**`) and DVR do not interact with each other.

### Parity-critical behaviors (top 5 for a reimplementation)
1. **Catch-up URL construction** — the five-way detection (attrs → catchupSource → Xtream live-URL regex) and the exact template/strftime semantics of `fillTemplate` + the `timeshift/{user}/{pass}/{mins}/{Y-m-d:H-M}/{id}.ts` and Flussonic `{stem}-{start}-{duration}.{ext}` shapes. Getting any of these wrong breaks replay for most providers.
2. **EPG tvg-id disambiguation** — shared tvg-ids across HD/SD/backup variants must be validated against channel-name tokens or users see wrong listings; plus the per-channel `tvg-shift` + global offset shift pipeline.
3. **Decorative-row filtering** (parse-time symbol rows + display-time divider patterns) — without it every real-world playlist shows junk "channels".
4. **Xtream session semantics** — `player_api.php?username&password` auth check (auth=0 / expired / banned / disabled), `allowed_output_formats`-driven ts/m3u8 container pick, https-port stream-base swap, and `get_short_epg` base64 title decoding as the EPG fallback for ≤120 channels.
5. **DVR via external mpv `--stream-record`** — the exact flag set (`--vo=null --ao=null --force-window=no --idle=no --cache=yes --network-timeout=60`, VLC UA), 2-second progress/exit watchdog loops, kill-on-finalize, and the in-memory (non-persistent) session model.
