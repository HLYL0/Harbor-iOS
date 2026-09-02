# Harbor Forensic Audit — Sync Services, Debrid, Downloads, Local Library, Storage, Security

**Subject:** Harbor (Stremio client) `src/` (TypeScript/React) + `src-tauri/src/` (Rust)
**Audit scope:** Trakt / Simkl / AniList / MAL sync, debrid integrations, downloads, local library, storage layout, backup/restore, profiles/PIN/parental, privacy blocking, Discord RPC + webhooks, updater, torrent engine.
**Method:** static source inspection. Every claim carries a file path. Explicit `FACT`/`INFERENCE` markers in §11.

---

## 1. Trakt (`src/lib/trakt/*`) — full API surface

### 1.1 Authentication (device flow + server-side secret proxy)
- Config (`config.ts`):
  - `TRAKT_API_BASE = https://api.trakt.tv`, API v2.
  - `TRAKT_CLIENT_ID = 71ef7ea86333eab031c8830f8200df1f2f16ef9a3335a67470be4950ac80b925` — hard-coded PUBLIC client id.
  - `TRAKT_TOKEN_PROXY = https://harbor.site/api/trakt/token` — token exchange/refresh is delegated to Harbor's server (holds the client **secret**).
  - `TRAKT_DEVICE_TOKEN_PROXY = https://harbor.site/api/trakt/device-token` — device-code→token exchange also proxied.
  - `TRAKT_VERIFY_URL = https://trakt.tv/activate`, `REFRESH_THRESHOLD_SEC = 14 days`, `WRITE_MIN_INTERVAL_MS = 1000`.
- Flow (`device-auth.ts`):
  1. `POST api.trakt.tv/oauth/device/code {client_id}` **directly from the client** → `device_code`, `user_code`, `verification_url`, `expires_in`, `interval`.
  2. User opens `trakt.tv/activate`, enters code.
  3. Poll `harbor.site/api/trakt/device-token {code}` → 200 = tokens; 400 = pending; 429 = slow_down (+5s interval); 410 = expired; 418 = denied.
  4. `fetchUsername()` calls `GET api.trakt.tv/users/me`.
- Token refresh (`client.ts`): on HTTP 401 → `POST harbor.site/api/trakt/token {refresh_token, grant_type:"refresh_token"}`; single in-flight refresh deduped; on failure session is cleared.
- Rate limiting (`client.ts`): HTTP 429 → wait `min(max(retry-after,1),30)`s, **one** retry.
- Session storage (`session.ts`): `localStorage` key `harbor.trakt.session.v1.<profileId>` (per-profile). Legacy migration reads `harbor.settings` fields `traktAccessToken/traktRefreshToken/traktExpiresAt/traktUsername` and promotes them. `isAuthenticated()` treats token as valid until `createdAt+expiresIn+14d` (refresh threshold).

### 1.2 API surface used (endpoint inventory)
| Area | Endpoint | File |
|---|---|---|
| Scrobble start/pause/stop | `POST /scrobble/{start,pause,stop}` | `scrobble.ts`, `scrobble-hook.ts` |
| History read | `GET /sync/history?limit=200` / `limit=1000` | `history.ts` |
| History write (mark watched) | `POST /sync/history` | `history.ts` |
| Watchlist read | `GET /sync/watchlist?sort_by=added&sort_how=desc` | `watchlist.ts` |
| Watchlist add/remove | `POST /sync/watchlist`, `POST /sync/watchlist/remove` | `watchlist.ts`, `watchlist-sync.ts` |
| Ratings set/remove/get | `POST /sync/ratings`, `POST /sync/ratings/remove`, `GET /sync/ratings/{movies,shows,episodes}?tmdb=|imdb=` | `comments.ts` |
| Recommendations | `GET /recommendations/{movies,shows}?limit=40&ignore_collected=true` | `recommendations.ts` |
| My calendar (up-next) | `GET /calendars/my/shows/{today}/{days}` (14d), `GET /calendars/my/movies/{today}/{days}` (30d) | `calendar.ts` |
| Anticipated rails | `GET /shows/anticipated?extended=full&limit=100`, `GET /movies/anticipated?...` (unauthenticated) | `calendar.ts` |
| Public lists | `GET /lists/{id}/items?page=&limit=` (unauthenticated) | `lists.ts` |
| Comments | `GET .../comments/{likes|newest...}`, `GET /comments/{id}/replies`, `POST /comments`, `POST|DELETE /comments/{id}/like`, `DELETE /comments/{id}` | `comments.ts` |
| User | `GET /users/me` | `device-auth.ts` |
| Home rails | recommended/anticipated collections (via `home-rails.ts` → recommendations/calendar) | `home-rails.ts` |

**Not implemented:** Trakt personal lists management (create/edit), collection sync (`/sync/collection`), `up-next` from playback progress is **not** Trakt — see Simkl §2.

### 1.3 Scrobble engine (`scrobble-hook.ts`) — merge/report rules
- Ignores media shorter than `STUB_MAX_SEC = 150` (no scrobbling of stubs).
- `WATCHED_MARK_PCT = 70`: playback crossing 70 % ⇒ send `stop` at progress 100 (Trakt auto-marks watched).
- Start → `scrobble start`; pause → `scrobble pause` **only if** setting `pauseListStatusOnPause` is on.
- Seek detection: 1 s interval sampler; a jump (>8 s and rate >4 s/s, or >8 s in <1.5 s) re-fires `start` at the new position, throttled to 1/30 s.
- On `pagehide`/unmount: `navigator.sendBeacon` to `POST /scrobble/{stop|pause}` with `keepalive:true` using the raw bearer token.
- On `stop` HTTP 409 → `already-recorded` (no retry storm); on other stop failure → **fallback `POST /sync/history`** (`provider.tsx` `scrobble()`).
- ID mapping (`ids.ts`): `ttNNNNNN` → movie or `ttNNNNNN:s:e` episode; `tmdb:movie:N`, `tmdb:tv:N[:s:e]`; `kitsu:`/`mal:` episodes only when an `imdbId + imdbSeason + imdbEpisode` hint is supplied, otherwise refused (`reason:"anime"`). Shows are never scrobbled directly.
- Watched-state flags for the Stremio library (`library-key.ts`): builds `imdb:tt…` / `tmdb:N:s:e` key sets from `GET /sync/history` and intersects with library items.
- Watchlist import/export (`watchlist-sync.ts`): export Stremio library → Trakt watchlist in chunks of 100, **skips anime ids** (`kitsu|mal|anilist|anidb:`), only `tt*`/`tmdb:*` ids; import Trakt → `saveStremioBookmark` per item (one by one, best-effort).
- Hydration (`hydrate.ts`): Trakt items enriched via TMDB detail (if user `tmdbKey` present) else Cinemeta by IMDb; concurrency 20; skeleton kept if enrichment fails.

### 1.4 Trakt client security notes
- `trakt/client.ts` uses raw browser `fetch` (not `safeFetch`) — **privacy blocklist does not apply to Trakt traffic** (see §9).
- Session JSON in localStorage: `accessToken`, `refreshToken`, `createdAt`, `expiresIn`, `username` — plaintext, per-profile.
- The client secret never ships client-side; all sensitive token ops go through `harbor.site`.

---

## 2. Simkl, AniList, MAL

### 2.1 Simkl (`src/lib/simkl/*`) — deepest sync integration
- Auth: **PIN flow**. `POST /oauth/pin` (no auth) → user enters PIN at `simkl.com/pin` → poll `GET /oauth/pin/{user_code}` until `result:"OK"` + `access_token` (`device-auth.ts`). Simkl OAuth tokens are long-lived; no refresh logic (`session.ts` `isAuthenticated()` = session exists).
- Config (`config.ts`): `SIMKL_API_BASE=https://api.simkl.com`, `SIMKL_CLIENT_ID=9609ef0a6051b6fdcf3290fd962fd65e0f8e969c942555410cffd37afca91997`, app-name `harbor`, app-version `0.9.75`. Client sends `simkl-api-key` header **and** `client_id/app-name/app-version` query params on every call (`client.ts`).
- Session key: `harbor.simkl.session.v1.<profileId>`.
- 429: exponential backoff 1s,2s,4s,8s,16s ×5 retries; 401 ⇒ session cleared.
- **Endpoints:**
  - `GET /sync/all-items/{movies,shows,anime}/all?extended=full&episode_watched_at=yes` — bootstrap full dump.
  - `GET /sync/all-items?date_from=<ts>` — **delta sync**.
  - `GET /sync/activities` — change timestamps (`all`, `rated_at`, `removed_from_list`) → drives delta + removal detection (`activities/sync.ts`).
  - `GET /sync/all-items?extended=simkl_ids_only` — authoritative id set after removals.
  - `GET /sync/all-items/all/{plantowatch,watching,completed}?extended=full` — watchlist/status browsing (`watchlist.ts`, `list-status.ts`, `history.ts`).
  - `POST /sync/add-to-list` (status change), `POST /sync/history` (mark watched + add), `POST /sync/history/remove`, `POST|GET /sync/ratings`, `GET /sync/ratings/...`.
  - `GET /sync/playback?hide_watched=true&limit=40` — **Up Next** (in-progress items, `playback.ts`).
  - `POST /scrobble/{start,pause,stop}` (`scrobble.ts`).
  - `GET /users/settings` (POST too) — avatar (`profile.ts`).
  - `GET /movies/{id}`, `GET /anime/{id}` — metadata (`anime-grouping.ts`, `ratings.ts`).
  - CDN: `https://data.simkl.in/calendar/{catalog}.json`, `https://data.simkl.in/discover/trending/today_100.json` (`home-rails/cdn.ts`) — **public unauthenticated** calendar data used for Up Next matching and rails.
- **Local cache & merge rules** (`activities/store.ts` + `sync.ts`): full catalog cached in `localStorage` key `harbor.simkl.cache.v2.<profileId>` with cross-index maps `imdbToSimkl`, `tmdbToSimkl`, `malToSimkl`, `kitsuToSimkl`. Merge strategy: per-item field-wise "new data wins, old data fills gaps" (`title/year/status/userRating/watchedAt/watchedEpisodes/poster` with `??` fallbacks). Watched episodes stored as `"S:E"` strings. Removals detected by comparing `removed_from_list` activity timestamps vs lastSync, then pruning against the ids-only dump. Statuses recognized: `watching|plantowatch|hold|completed|dropped`.
- Up Next (`home-rails/up-next.ts`): CDN calendar items matched against cache via simkl/imdb/tmdb/mal/kitsu ids; only items in `watching`/`plantowatch` state, next 30 days.
- Watchlist ratio: `WATCHED_RATIO=0.85`, `SIMKL_WATCHED_RATIO=0.8` (`config.ts`).

### 2.2 AniList (`src/lib/anilist/*`)
- GraphQL at `https://graphql.anilist.co`; `client.ts` handles 429 (retry-after ≤30 s, 1 retry).
- Auth: OAuth2 **authorization code + PIN redirect** (`auth.ts`): `https://anilist.co/api/v2/oauth/authorize?client_id=42941&redirect_uri=https://anilist.co/api/v2/oauth/pin&response_type=code` → user pastes the code → exchanged via **Harbor proxy** `https://bugs.harbor.site/v1/anilist/token` → access token. **No refresh token** — hard-coded TTL `31536000` s (1 year) assumed after issue (`DEFAULT_TOKEN_TTL_SEC`); `isAuthenticated()` = `now < expiresAt`.
- Session key: `harbor.anilist.session.v1.<profileId>` (accessToken, createdAt, expiresAt, userId, userName, avatar).
- Surface:
  - Queries: `Viewer`, `MediaListCollection(userId, ANIME)` (list groups, cached in `harbor.anilist.collection.v1.*`), `Page` browse/search/top (`browse.ts`, `use-anilist-top.ts`), `Media(id)` detail/art/relations/threads (`browse.ts`, `relations.ts`, `threads.ts`), recommendations (`recommendations.ts`).
  - Mutations (`mutations.ts`, `sync.ts`): `SaveMediaListEntry(mediaId, status, progress)`, `DeleteMediaListEntry`, status→`CURRENT/COMPLETED`.
- Progress sync (`sync.ts`): only for ids `anilist:`/`kitsu:`/`mal:` (kitsu via static `kitsuToAnilist` map, mal via GraphQL `Media(idMal)`); monotonic guard — per-profile sent-map `harbor.anilist.synced.v1.<profileId>` (`harborId → lastEpisode`); never regresses (`ep <= current` ⇒ update map, no write); `episodes` total known ⇒ status `COMPLETED` at final episode else `CURRENT`; auto-mark `CURRENT` when previously `PLANNING` (`markAnimeWatching`). In-flight dedupe keyed `harborId|ep`. 401 silently ignored.
- Settings switch `anilistAutoSync` (default **on**, migration `_anilistSyncOnV1` in `settings/load.ts`).

### 2.3 MyAnimeList (`src/lib/mal/*`)
- REST `https://api.myanimelist.net/v2`, `MAL_CLIENT_ID=879be1ac300dc70611e5c828fec7bc18`.
- Auth: OAuth2 code + **PKCE plain** (`auth.ts`): `myanimelist.net/v1/oauth2/authorize?response_type=code&code_challenge=<verifier>&code_challenge_method=plain`; user pastes code; exchange + refresh via **Harbor proxy** `https://harbor.site/api/mal/token`. Verifier held in memory only (64-char random) — refresh works only after completed authorization in the same session. Uses `@tauri-apps/plugin-http` fetch on desktop to dodge CORS.
- Session key: `harbor.mal.session.v1.<profileId>` (accessToken, refreshToken, createdAt, expiresAt, userName).
- Surface: `GET /anime/{id}?fields=...`, `PATCH /anime/{id}/my_list_status` (form-encoded: `status`, `num_watched_episodes`), `GET /users/@me` (username/validation), list browsing (`lists.ts`), score badge (`mal-rating.ts`, `showMalBadge` setting).
- Progress sync (`sync.ts`): mirror of AniList logic — sent-map `harbor.mal.synced.v1.<profileId>`, monotonic, `plan_to_watch→watching` promotion, `completed` at final episode, confirm-response check (`num_episodes_watched === ep`).
- Both anime trackers are **push-only progress trackers** — they do not pull watch-state back into the UI library (except via AniList collection rails).

---

## 3. Debrid services (`src/lib/debrid/*`)

### 3.1 Providers
`registry.ts` builds clients from settings fields — `rdKey` (Real-Debrid), `tbKey` (TorBox), `adKey` (AllDebrid), `pmKey` (Premiumize), `dlKey` (Debrid-Link). Non-empty key ⇒ client exists. Keys live in `harbor.settings` (localStorage + `settings.json` on disk), **plaintext** — and are exported in `.harbx` backups (§7).

Common contract (`types.ts`): `account()`, `cacheCheck(hashes)`, `playableUrl(magnet, fileIdx, signal, hint)`, `listLibrary()`, optional `queueCache()`. `hashFromMagnet` extracts BTIH lowercased; `magnetFromHash` rebuilds `magnet:?xt=urn:btih:<hash>`.

| Provider | BASE | account | cache check | resolve→playable | library | misc |
|---|---|---|---|---|---|---|
| Real-Debrid | `api.real-debrid.com/rest/1.0` | `GET /user` | **stub — returns `{}` always** (`cacheCheck` unimplemented; unused `cacheCheckBatch`) | `POST /torrents/addMagnet` → poll `GET /torrents/info/{id}` (600 ms ×18 ≈ 10.8 s) → `POST /torrents/selectFiles/{id}` (video exts or episode-hint match) → `POST /unrestrict/link` | `GET /torrents?limit=100&page=1..5`, only `downloaded`, 5-min in-memory TTL per key | deletes torrent on abort/magnet_error/no-video/not-cached/error/virus/dead/timeout (`DELETE /torrents/delete/{id}`) |
| AllDebrid | `api.alldebrid.com/v4` | `GET /user` | `POST /magnet/instant` (real batch cache check) | `POST /magnet/upload` → poll `GET /magnet/status?id=` → `GET /link/unlock` (+ `GET /link/delayed?id=` for delayed links) | `GET /magnet/status` (no id) | — |
| Premiumize | `www.premiumize.me/api` | `GET /account/info` | `GET /cache/check?items[]=...` | `POST /transfer/directdl {src}` → poll `GET /transfer/list` | `GET /transfer/list` (completed) | — |
| Debrid-Link | `debrid-link.com/api/v2` | `GET /account/infos` | `GET /seedbox/cached?url=<hashes csv>` | `POST /seedbox/add` → poll `GET /seedbox/list?ids=` → link | `GET /seedbox/list?perPage=50&page=` | cleanup `DELETE /seedbox/{id}/remove` on failures |
| TorBox | `api.torbox.app/v1/api` | `GET /user/me` | `GET /torrents/checkcached?hash=&format=...` | `POST /torrents/createtorrent` → poll `GET /torrents/mylist?id=&bypass_cache=true` → `GET /torrents/requestdl?token=<apiKey>&torrent_id=&file_id=&zip_link=false` | `GET /torrents/mylist?bypass_cache=true` | API key appears **in URL** on requestdl |

### 3.2 Error mapping / timeouts (per provider `wrap()`)
- RD: 401/403 ⇒ `unauthorized` (or `not-premium` if body mentions subscription/premium); 402 ⇒ `not-premium`; 429 ⇒ `rate-limited`; 503/504 ⇒ `upstream-unavailable`; AbortError ⇒ `aborted`; parse fail ⇒ `parse-error`; else raw error code.
- All requests go through `safeFetch`; on desktop → native `harbor_fetch` (reqwest, 30 s default timeout, hickory DNS, `no_proxy`); on web → `/api-proxy/<host>` VPS relay with `Authorization` rewritten to `x-harbor-auth` (Torrentio/TorBox-API are the only direct-host exceptions due to Cloudflare).
- All debrid calls accept an `AbortSignal`; aborts clean up the torrent they created.

---

## 4. Downloads

### 4.1 What is downloadable
Any direct **HTTP(S) URL** a stream resolves to — including debrid-restricted links (custom headers forwarded) — via `enqueueDownload({meta, episode, streamLabel, url, headers})` (`download/downloads-store.ts`). Torrent-internal files are **not** in this pipeline (torrent streaming is playback-only; see §6.5).

### 4.2 Manager state (`downloads-store.ts`)
- In-memory `Map` + persisted snapshot in localStorage `harbor.downloads.v1` (fields: id, metaId, title, subtitle, poster, season/episode, streamLabel, url, path, status, receivedBytes, totalBytes, ratio, bytesPerSec, error, startedAt).
- Statuses: `downloading | done | error | canceled | interrupted` — on hydrate, any leftover `downloading` is demoted to `interrupted` (**no auto-resume of the manager**; Rust resume is per-attempt, §4.4).
- Progress events throttle: ≥250 ms or ≥4 MB (`download.rs`). Speed computed client-side every ≥500 ms.
- Cancel (`download_cancel` → AtomicBool) and remove (aborts + deletes file **and** `.part`).

### 4.3 Storage location
- `settings.downloadDir` if set, else OS default Downloads dir; optional `downloadCreateFolders` creates a per-title folder (sanitized name). Filename from `buildDefaultFilename(meta, episode, url, streamLabel)`; collision ⇒ `Name (2).ext … (999)`.

### 4.4 Rust engine (`src-tauri/src/download.rs`)
- Writes to `<dest>.part`, opens in append mode.
- **Resume:** if `.part` exists, sends `Range: bytes=<len>-`; on `206` continues from byte offset; on `416` renames part→dest and reports Done.
- Browser UA spoof (`Chrome/126`). Always sends `Range: bytes=0-` on fresh starts.
- **Content validation:** rejects `text/*|html|json|xml` content types or <64 KiB; after stream end, deletes `.part` if received <512 KiB (`MIN_VIDEO_BYTES`) — "not a video" guard. 500-char snippet of rejected bodies logged (host redacted, `log_host()` prints scheme://host only).

---

## 5. Local library

### 5.1 Entries & scanning
- Catalog stored in `localStorage` key `harbor.library.local.v1` (`local-library.ts`): `{id, path, filename, title, year, type, resolution, rating, runtime, poster, tmdbId, imdbId, season, episode, addedAt, needsReview, source:"tmdb"|"nfo", localArt}`.
- Scan: Rust `harbor_scan_folder` (`local_lib.rs`): WalkDir **max depth 8**, `follow_links(false)`, video exts (`mkv mp4 m4v mov avi wmv webm ts m2ts mpg mpeg flv ogv`), min file size default **50 MB** (setting `localMinFileSizeMb`). Returns path/filename/size; parsing happens in TS.
- Filename parsing (`parseFilename`): TV regex `SxxExx|NxN|Season x Episode x`; year `19xx|20xx`; resolution `2160p|1080p|720p|480p|4k|uhd`; noise-word stripping (codecs, groups, HDR tags, release groups like `yify/rarbg/fgt/evo/psa`); bracketed groups removed.
- Series matching: by `imdbId` or normalized title (`localShowEpisodes`); `findLocalEpisode/findLocalMovie/findLocalEpisodeByIds` used to inject "watched/available locally" signals into catalog pages.

### 5.2 Metadata sidecars (`local-library/sidecars.ts`)
- NFO discovery: `<stem>.nfo`, `movie.nfo`, `tvshow.nfo` (show: dir + parent). DOMParser XML: title/originaltitle/showtitle, year (year|premiered|aired|releasedate), plot/outline, rating, runtime, `uniqueid type=tmdb|imdb`, legacy `id` (`tt*` ⇒ imdb, numeric ⇒ tmdb), thumb art (aspect poster/clearlogo/logo/clearart/landscape/fanart).
- Artwork discovery: `<stem>-poster.jpg/png`, `poster.jpg`, `folder.jpg`, `cover.jpg`; `<stem>-fanart`, `fanart`, `backdrop`; `<stem>-clearlogo/-logo`, `clearlogo`, `logo`; per-season `seasonXX-poster.jpg/png`. Directory index cached per dir (`clearSidecarCache()`).

### 5.3 NFO export (`local-library/export.ts`)
Writes Kodi-style sidecars **next to the media**: movie `<stem>.nfo`; series `tvshow.nfo` + per-episode `<stem>.nfo` (season dir detected via `/^(specials|s\d{1,2}|season[\s._-]*\d{1,2})$/i`); downloads TMDB artwork to `<stem>-poster.ext`, `<stem>-fanart.ext`, `<stem>-clearlogo.ext`, `poster.*`, `fanart.*`, `clearlogo.*`, `seasonNN-poster.*` (needs user `tmdbKey`; TMDB ids required). Episode info via `tmdbSeasonEpisodes` cache.

### 5.4 Playback
`localPlayerSrc` (`player-src.ts`) passes `url: entry.path` (local file path) with `notWebReady: true` — mpv plays the file directly.

---

## 6. Storage layout

### 6.1 WebView `localStorage` (primary app state; lives in the WebView profile dir)
Namespaced `harbor.*`. Notable keys:
- **Settings:** `harbor.settings` (legacy mirror), `harbor.settings.shared`, `harbor.settings.<profileId>` (per-profile fork). Contains **all** secrets: `rdKey, tbKey, adKey, pmKey, dlKey, tmdbKey, omdbKey, rpdbKey, fanartKey, tvdbKey, tvdbPin, mdblistKey, auddKey, aiSearchKey, aiGroqKey, jinaKey, opensubtitlesApiKey, jimakuToken, traktClientId/Secret/…, togetherCfToken, discordUrl, telegramUrl` (`settings/types.ts`).
- **Auth:** `harbor.auth.<profileId>` (Stremio authKey + user), `harbor.trakt.session.v1.<p>`, `harbor.simkl.session.v1.<p>`, `harbor.anilist.session.v1.<p>`, `harbor.mal.session.v1.<p>`, `harbor.letterboxd.session.v1`.
- **Profiles:** `harbor.profiles.v1` (profile list + activeId + passwords/PIN hashes/kid config).
- **Catalogs/caches:** `harbor.simkl.cache.v2.<p>`, `harbor.anilist.collection.v1.*`, `harbor.downloads.v1`, `harbor.library.local.v1`, `harbor.feed-prefs.v2` (votes), `harbor.custom-themes.v1`, `harbor.customlists.v1`, `harbor.anilist.synced.v1.<p>`, `harbor.mal.synced.v1.<p>`, `harbor.calendar.webhook.last`, `harbor.curfew.<profileId>`, `harbor.update.dismissed`, etc.
- **Feed preferences** (`feed/preferences.ts`): `harbor.feed-prefs.v2` — `{votes:{metaId:{vote,ts,name,type,altId}}, updatedAt}` with v1 migration.
- **Pruning** (`storage-recovery.ts`): ~45 exact + 2 prefix patterns (`harbor.anilist.collection.v1.`, `harbor.libraryNameRepair.v1.`) of cache keys removable via UI.
- **IndexedDB:** `harbor-theme` DB (store `kv`, key `bg`) holds the background image (base64), legacy fallback `harbor.theme.bg` (localStorage) (`theme-storage.ts`).

### 6.2 Rust-side files (Tauri `app_data_dir` / `app_cache_dir` / temp)
- `settings.json` in app data dir — **mirror of settings written by frontend** via `settings_read/settings_write` (atomic tmp+rename); Rust reads `torrentsDisabled` from it cheaply (`settings_store.rs`).
- `crash-recovery/panic.json` + `crash-recovery/running` marker (PID) — panic hook writes kind/version/platform/message/location/backtrace (≤64 KB); `running` removed on clean exit; next launch offers the report (`crash_report.rs`).
- Torrent engine: `app_cache_dir/engine` (session persistence `engine.json`) or `<custom>/harbor-stream-cache` if user set a custom torrent cache dir (`torrent_engine.rs` lines 224–246). Cache sweeper runs every 30 min after 60 s, deleting oldest content while preserving live files (`cache_sweep.rs`).
- mpv demux cache: `app_cache_dir/mpv-cache` (64 MiB back-bytes, 300 s readahead); subtitle temp: `temp/harbor-subs`; trickplay thumbs: `temp/harbor-thumbs/<session>`.
- WebView itself: default WebKit/WebView2 profile storage.

### 6.3 Settings loading / versioning (`settings/load.ts`)
- Single giant object `Settings` with `DEFAULT` (`defaults.ts`); stored JSON merged over defaults with per-section fallbacks.
- **Flag-based migrations:** `_pickerLayoutStremioV2`, `_stremioDeeplinkOnByDefault`, `_anilistSyncOnV1`, `_rememberLastStreamOnV1`, `_streamSortAddonV1`, `_mpvEmbedV3/V4`, `_anime4kIndicatorOffV1`, `_subStyleV2/_subAssForceV1/_subAssRespectV2` — one-shot behavior migrations; `scrapers/scrapersAcknowledged/_scrapersV2` keys deleted outright.
- Sanitization: theme preset/font/custom colors (hex regex), seek steps, poster dock transition (250–1500 ms), language codes, `aiSearchModel` id migration.
- Profile linking (`profile-store.ts`): profiles may share settings (`harbor.settings.shared`) or fork (`harbor.settings.<id>`); `MIRROR_KEY` always receives the last effective blob; legacy recovery path exists (`recoverableLegacyBlob`/`applyLegacyToActive`).
- No numeric schema version on the settings blob itself — migrations are presence-flag based.

---

## 7. Backup / Restore — `.harbx` format (`src/lib/backup.ts`)

```
{
  "format": "harbor-backup",
  "version": 1,
  "app": "<__APP_VERSION__>",
  "exportedAt": "ISO-8601",
  "data": { "<localStorage key>": "<raw string value>", ... },
  "bgImage": "<base64|null>"
}
```
- File: `harbor-backup-<YYYY-MM-DD>.harbx` — plain (uncompressed, unencrypted) pretty-printed JSON with a custom extension.
- Export: iterates **all** localStorage entries starting with `harbor.`, applying `isPortable()` exclusions: **only** `harbor.auth` / `harbor.auth.*` and `harbor.together.clientId` are dropped.
- Restore (`applyBackup`): deletes every existing portable key, then re-inserts from file; same `isPortable` filter on import; bgImage restored via IndexedDB.

### 7.1 Secrets exposure (FACT)
The exclusion list is tiny, so a `.harbx` file **contains**:
- All debrid API keys (`rdKey, tbKey, adKey, pmKey, dlKey`), TMDB/OMDb/RPDB/Fanart/TVDB keys, OpenSubtitles key, Jimaku token, AI provider keys — everything inside `harbor.settings*` blobs.
- **Trakt/Simkl/AniList/MAL session tokens** (`harbor.trakt.session.v1.*`, `harbor.simkl.session.v1.*`, `harbor.anilist.session.v1.*`, `harbor.mal.session.v1.*`) — including refresh tokens and, for MAL, a still-valid refresh token usable via the `harbor.site/api/mal/token` proxy.
- Webhook URLs (`discordUrl`, `telegramUrl` — full tokens in URL), IPTV playlist URLs (often embedded credentials), profile password/PIN hashes (SHA-256 — see §8).
- **Excluded:** the Stremio account session (`harbor.auth.*`) and Together client id only.

---

## 8. Profiles, PIN, parental controls

- Profiles live in `harbor.profiles.v1`: `{profiles:[{id,name,avatar?,isPrimary,shareStremioWith,passwordHash,hideContent,lockedTabs,kid:{age,curfewMinutes,parentPinHash}}], activeId}` (`profiles.tsx`). Each profile can bind a separate Stremio login (`harbor.auth.<id>`, `shareStremioWith` = which profile's Stremio account is used).
- **PIN hashing** (`profile-password.ts`): `SHA-256("harbor-profile-v1|" + pin)` via WebCrypto — **static salt, no KDF**; PINs are 4-digit-class entropy ⇒ trivially brute-forceable offline from a settings/profile blob or `.harbx`. Kid `parentPinHash` uses the same scheme.
- Parental flow (`parental.tsx`): PIN gates access to *locked tabs* (`lockable-tabs.ts` `HiddenTabs`); a profile is `locked` when it has a `passwordHash` AND any tab locked; unlock is session-scoped (`sessionUnlockedFor`, reset on profile switch); legacy key `harbor.parental` migrated (hiddenTabs + pinHash) — and that legacy key is prunable via storage-recovery.
- Content hiding: `hideContent` (adult/titles) + kid `age` filters; curfew: `kid.curfewMinutes` per day tracked in `harbor.curfew.<profileId>` `{date, seconds, unlocked}` (`curfew.ts`) — daily play-time budget.
- Settings for kids are `password: string` under some sub-object (`settings/types.ts` line ~451) — profile password (non-hashed) present in settings for login UX (INFERENCE — exact field context beyond the type def wasn't fully traced).

---

## 9. Privacy blocker (`src/lib/privacy/blocklist.ts` + `safe-fetch.ts`)

- Static denylist: ~85 exact hosts + 35 domain suffixes (Google Analytics/Tag Manager/ads, DoubleClick, Yandex Metrika, Meta pixel, TikTok/Twitter analytics, Hotjar, Mixpanel, Amplitude, Segment, FullStory, Matomo, wp.com stats, Bing, Clarity, Branch, AppNexus, Rubicon, PubMatic, Casale, Criteo, Taboola, Outbrain, pop-under/ad networks).
- Enforcement point: `safeFetch()` — before any fetch, `isBlockedUrl()` rejects with `TrackerBlockedError` and increments the blocked counter (shown in UI).
- Toggle: `setTrackerBlocking(on)` (setting).
- **Coverage caveats (FACT):** the filter only applies to code paths using `safeFetch`. Raw `fetch` call sites bypass it — notably `trakt/client.ts`, `trakt/device-auth.ts`, `anilist/client.ts`, and the webhook engine (`calendar.ts` fireWebhook). Downloads run in Rust (reqwest) — not filtered. The dedicated auxiliary browser window (`browser.rs`) injects only an Escape-to-close script and (Linux) stremio:// capture — **no ad-blocking there**.

---

## 10. Discord Rich Presence + webhook/Telegram notifications

- **Rich Presence** (`discord/presence.ts` + `src-tauri/src/discord_rp.rs`): TS computes a presence payload (title/state/poster/timestamps/party) and calls `discord_set_enabled/set_presence/clear`; Rust uses the `discord_rich_presence` crate over local Discord IPC with `APP_ID=1510339683215736892`. No Discord credentials are stored — it's the local client's IPC. Options: `hideTitle` ("Watching something"), `showWhenPaused`, `showWhenBrowsing`, `showPoster` (image URLs must be `https://` and ≤256 chars), `showTimestamp` (start/end ts), `showPartyJoin` (join button w/ watch-party URL). Debounced flush 800 ms; seek ≥4 s forces re-push. Fallback logo `harbor.site/discord/harbordiscord.png`.
- **Webhook engine** (`webhook-engine.ts` + `calendar.ts`): `settings.webhooks = {discordUrl, telegramUrl, sources, notifyMovies/Tv/Anime, rules[]}`. Trigger sources: library calendar, Trakt my-calendar, Trakt anticipated, custom TMDB calendar (tracked people/genres/providers/countries), and per-rule live-IPTV-EPG events. Baseline-on-first-seen + per-item dedupe persisted in `harbor.calendar.webhook.last` (`LastFiredState`, 60-day prune); fire window = next 2 days, track window = 14.
- Discord message: JSON webhook `{username:"Harbor", content, embeds[]}`; Telegram: Bot-API style POST to the user-supplied URL with `chat_id` extracted from the URL, `parse_mode: Markdown`, ≤8 items, preview disabled. Failure to persist state aborts firing to prevent spam.

---

## 11. FACT vs INFERENCE

### FACT (verified in source)
1. Trakt device-auth is direct-to-Trakt for the code but proxied through `harbor.site` for token exchange (client secret never client-side).
2. Trakt cache check for Real-Debrid is a stub returning empty — RD availability in pickers is **not** implemented via `/torrents/instantAvail` style batch; RD playback resolves add→poll→unrestrict live (10.8 s cap).
3. Debrid keys are plaintext in `harbor.settings*` and exported inside `.harbx`; only `harbor.auth*`/`harbor.together.clientId` are excluded from backups.
4. Profile PIN = SHA-256 of static salt + PIN (fast hash, no iteration) — offline brute-force feasible.
5. AniList uses an assumed 1-year token TTL with no refresh mechanism.
6. MAL uses PKCE with `code_challenge_method=plain` (not S256) and a server-side token proxy.
7. Downloads resume via HTTP Range against a `.part` file, but the app does not auto-resume interrupted items after restart (status → `interrupted`).
8. Privacy blocklist is enforced only inside `safeFetch`; Trakt/AniList/webhook/rust-download paths are not filtered.
9. `.harbx` is unencrypted JSON; includes live refresh tokens for Trakt/MAL and all API keys.
10. Torrent engine (librqbit) persists in `app_cache_dir/engine` (or `<custom>/harbor-stream-cache`), serves via an axum router (`/stream/{hash}/{file_id}`, `/health`, `/settings`, `/{hash}/create`), with a 30-min cache sweeper.

### INFERENCE (not directly verifiable in this repo)
- The `harbor.site` / `bugs.harbor.site` proxies hold Trakt/MAL/AniList client secrets; their logging/retention is unknown.
- Whether `settings.json` (disk) or localStorage is authoritative depends on the frontend write path (`settings.tsx`), not fully traced here; both exist and both contain secrets.
- The `password` field in `Settings` (line ~451 of `settings/types.ts`) is inferred to be a kid-profile login password; context suggests it is stored non-hashed alongside the profile `passwordHash`.
- Simkl tokens are assumed non-expiring because no refresh path exists; if Simkl expires them, users must re-PIN.
- Telegram delivery assumed to be Bot API `sendMessage`-shaped (custom URLs with `chat_id` query).

---

## 12. Top 5 parity-critical behaviors (for reimplementation)

1. **Trakt scrobbling state machine:** start on play (≥150 s media), pause only if `pauseListStatusOnPause`, stop at ≥70 % ⇒ progress 100 (watched), 409-tolerance on stop, `sendBeacon` on pagehide, seek-resync `start` (≤1/30 s), stop-failure fallback to `POST /sync/history`.
2. **Debrid playable-url protocol:** add magnet → poll status (RD 600 ms×18; timeout ⇒ delete + `not-cached`) → auto file selection (video extensions / episode-hint regex) → selectFiles → unrestrict/directdl/requestdl; every provider deletes its own transfer on abort/error; 401/402/429/503 semantics normalized (`unauthorized`, `not-premium`, `rate-limited`, `upstream-unavailable`).
3. **Backup `.harbx` semantics:** plain JSON `{format:"harbor-backup", version:1, data:{harbor.*}, bgImage}`; restore = wipe-all-portable-then-apply; portability filter excludes **only** `harbor.auth*` + `harbor.together.clientId` — secrets travel with the file (replicate or explicitly diverge).
4. **Settings storage & migration model:** one JSON blob per profile (`harbor.settings.<id>` / `.shared`) mirrored to `harbor.settings`, mirrored to `settings.json` in app-data; migrations are one-shot presence flags (e.g. `_anilistSyncOnV1` defaults `anilistAutoSync=true`); load = DEFAULT ∪ parsed ∪ per-section fallbacks + sanitizers.
5. **Tracker merge rules:** Simkl full→delta sync with per-item field-wise "new wins, gaps filled" merge + removal pruning via `activities` + ids-only dump, cached with id cross-index maps; AniList/MAL progress pushes are monotonic (sent-map guard, never regress, promote planning→current, completed at final episode) and 401-silent; Trakt watchlist import skips anime ids and exports in chunks of 100.
