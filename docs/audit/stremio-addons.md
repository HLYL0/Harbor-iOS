# Harbor Stremio Account + Addon System — Forensic Audit

**Target:** Harbor v0.9.21 (`package.json` version, repo root), a cross-platform Stremio client (Tauri 2 + React/TS + libmpv).
**Repo:** `C:/Users/Admin/AppData/Local/Temp/harbor-ref`
**Scope:** Stremio login/auth, addon manifest consumption, addon resource requests, install/uninstall/update/reorder/config, addon discovery store, deep-links, and failure handling.
**Convention:** every claim carries a file path. Sections marked `FACT` are code-verified; `INFERENCE` is clearly labeled.

---

## 1. Stremio login / auth flow (exactly as implemented)

### 1.1 Two sign-in paths

**Path A — "Sign in with Stremio" web OAuth-style flow (desktop only).**

1. `src/lib/stremio-auth.ts:14-48` — `startStremioWebAuth()`:
   - Requires Tauri (`__TAURI_INTERNALS__`), else throws.
   - Invokes Rust command `stremio_auth_start` → Rust binds an **ephemeral TCP listener on 127.0.0.1:0** (random port) and returns the port.
   - Opens `https://www.stremio.com/login?appName=Harbor&appCallback=http://127.0.0.1:<port>/cb` in the OS browser (`openUrl`).
   - Listens for the Tauri event `stremio-auth`; resolves with the raw `authKey`; **5-minute (300 000 ms) client-side timeout**.
2. `src-tauri/src/stremio_auth.rs:16-66` — `stremio_auth_start`:
   - axum server with one route: `GET /cb` — reads query params `key` **or** `authKey` (either accepted).
   - On receipt: emits Tauri event `stremio-auth` with the key, renders a static "You're signed in" HTML page, and shuts down via oneshot.
   - Server self-destructs after **300 s** if no callback arrives.
   - FACT: the auth key transits through the OS browser's query string → loopback callback. No PKCE, no code exchange — Stremio's login page redirects back with the raw key.

**Path B — email/password.** `src/lib/stremio.ts:109-115` `login(email, password)` POSTs `{ email, password, facebook: false }` to `https://api.strem.io/api/login` and returns `{ authKey, user }`. This API exists in the lib but the primary UI entry is Path A (`src/components/auth-modal/stremio-web-button.tsx:8-20` calls `startStremioWebAuth()` then `signInWithKey(key)`).

### 1.2 Key validation and session construction

- `src/lib/auth.tsx:107-116` — `signInWithKey(authKey)`:
  - Trims the key; calls `getUser(key)` (POST `https://api.strem.io/api/getUser`, `src/lib/stremio.ts:117-119`).
  - If `getUser` fails or returns no `_id`, Harbor **still accepts the session** and fabricates a placeholder user: `{ _id: "stremio:<key first 10 chars>", email: "" }`. FACT — a malformed/revoked key still produces a "logged in" state locally; only the placeholder's API calls will fail later.

### 1.3 Token storage & session persistence

- `src/lib/auth.tsx:22-49` — per-profile storage: `localStorage` key **`harbor.auth.<profileId>`** containing JSON `{ authKey, user }`. (Auth is per Harbor profile, not global.)
- Profile-to-Stremio-account mapping: `src/lib/profiles.tsx:522-527` `stremioSourceProfileId()` — if a profile has `shareStremioWith` set to another profile id, the auth session of that source profile is used (Stremio account sharing across Harbor profiles). A profile signing in with its own account clears `shareStremioWith` (`src/lib/auth.tsx:91-93`).
- `src/lib/auth.tsx:24,81-83` — module-global `liveStremioAuthKey` mirrors the active session so non-React modules (`addon-store.ts`) can read the key synchronously; `readActiveStremioAuthKey()` (lines 51-65) falls back to parsing `harbor.profiles.v1` + `harbor.auth.<id>` directly.
- Session survives restarts (localStorage) — **FACT: the auth key is persisted in plain text in the webview's localStorage** (same trust model as Stremio Web; not OS keychain).

### 1.4 Logout

- `src/lib/auth.tsx:118-129` — `signOut()` **only clears local state**: removes `harbor.auth.<profileId>` (or clears `shareStremioWith` if the profile was sharing). 
- `src/lib/stremio.ts:121-123` defines `logout(authKey)` (POST `api.strem.io/api/logout`) but **it is never called from `signOut`** — grep of `src/` shows `logout` invoked only in settings search-keyword lists (`src/views/settings/nav.tsx`). FACT: Harbor does **not** invalidate the server-side auth key on sign-out. INFERENCE: the Stremio session remains valid server-side; the key simply becomes unknown to this Harbor install.

### 1.5 Stremio API surface used (account scope)

All calls POST JSON to `https://api.strem.io/api/<method>` (`src/lib/stremio.ts:98-107`, `src/lib/addons.ts:82-95`): `login`, `getUser`, `logout` (unused), `addonCollectionGet`, `addonCollectionSet`, `datastoreMeta`, `datastoreGet`, `datastorePut` (library — outside addon scope but same transport). Responses are unwrapped from `json.result`; errors thrown from `json.error.message`.

---

## 2. Addon manifest schema fields Harbor reads

Type definition: `src/lib/addons.ts:19-40` (`Addon.manifest`). Fields Harbor actually consumes:

| Field | Where consumed |
|---|---|
| `id` | dedupe key everywhere; `addon-store.ts:240` requires non-empty; canonical id on install (`addon-store.ts:266`) |
| `name` | display, adult-text scan, family detect, slow-addon timeout match, dedupe (`addons-store/store.ts:15-27`) |
| `version`, `description`, `logo`, `background`, `contactEmail` | display / detail page; `logo`/`background` excluded from local storage if `data:` URIs (`addon-store.ts:89-94`); `description` truncated to 400 chars for storage (`addon-store.ts:85-88`) |
| `catalogs[]` (`id`, `type`, `name`, `extra[{name,isRequired,options}]`) | home rows (`addons.ts:282-327`), search (`search-addons.ts:24-44`), AIOStatus detection (`aiostatus.ts:74-77`) |
| `resources[]` (string OR `{name,types,idPrefixes}`) | capability gating for stream/meta/subtitles/catalog (`addons.ts:59-80`, `streams/addons.ts:121-144`, `meta-resource.ts:37`, `subtitles/providers/addons.ts:74-80`, categorization `addons-store/store.ts:337-340`) |
| `types[]`, `idPrefixes[]` | same capability gating; Torrentio synthesizes `["tt","kitsu"]` (`addons.ts:200`) |
| `behaviorHints.adult` | adult gating (`addons-store/store.ts:327`, `stremio-addons.ts:147-149,175-178`) |
| `behaviorHints.configurable`, `behaviorHints.configurationRequired` | route install to configure UI (`views/addons.tsx:197-200`) |
| `behaviorHints.p2p` | typed but not observed in gating logic (typed in `addons.ts:34`; no runtime use found) |

Local persistence slims the manifest to exactly: `id, name, version, description, logo, background, types, idPrefixes, resources, catalogs, behaviorHints` (`src/lib/addon-store.ts:64-76`), with catalogs reduced to `id/type/name/extra[{name,isRequired}]` (drops `options` — INFERENCE: options only matter at configure time, not for catalog requests).

**Stremio-side round-trip:** when pushing to the account, `addonCollectionSet` items include `transportUrl`, `transportName` (preserved if present, else `""`), `manifest`, and `flags: { official, protected }` defaulting false (`src/lib/addons.ts:106-124`).

---

## 3. Addon resource request flow

### 3.1 Streams (`stream`)

`src/lib/streams/addons.ts`:

- **Addon selection:** iterate addons in configured order (priority = array index, line 44). Skip status-only addons (AIOStatus family, `addon-detect.ts:23-25`). For each addon, `pickIds()` (lines 111-119) sorts candidate IDs by prefix priority `kitsu > mal > anidb > anilist > tt > tmdb` (lines 88-95) and picks accepted ids; if both an anime-scheme id and an `tt` id are accepted it queries **both** (max 2 requests/addon).
- **Acceptance test** `addonAcceptsId()` (lines 121-144): explicit `resources:[{name:"stream", types, idPrefixes}]` wins; else legacy `resources:["stream"]` + manifest `types`/`idPrefixes`.
- **URL construction:** `transportUrl` with trailing `/manifest.json` stripped + `/stream/<type>/<id>.json` (line 153).
- **Parallelism:** all addon tasks fire at once (`Promise.allSettled`, line 80). Results stream in with `onPartial(accumulated)` per completion — progressive UI.
- **Timeouts:** per-addon AbortController — **8 s** default, **22 s** for slow addons matching `/mediafusion|comet|torrentio|knightcrawler|aiostreams|jackettio|torbox/i` against name/id/url (lines 9-27, 154-160). Parent signal aborts all. Timeout → addon dropped (`[]`), others unaffected.
- **Retry:** **none at this layer** (no retry loop in `fetchOne`). A failed addon just contributes zero streams. (TanStack query retry applies only to catalog-level queries, see §3.5.)
- **Headers:** `Accept: application/json, text/plain, */*` + Chrome 130 desktop `User-Agent` (lines 166-170).
- **Enrichment:** every stream gets `addonId`, `addonName`, `addonUrl`, `addonRanked` (true only for aiostreams family, `addon-detect.ts:18-21`), `addonPriority` (addon index), `addonReturnIdx` (row order within the addon's response). `infoHash` lowercased. If no infoHash but the stream looks uncached (`hasUncachedMarker`, `streams/cached.ts`), Harbor parses an infohash from `url`/`sources` magnet (`torrent/magnet.ts`).
- **Dedupe:** key `addonId:hash:<infoHash>:<fileIdx>` or `addonId:url:<url|title|name|random>`; duplicates merge `sources` (lines 216-234). Note: dedupe is **per addonId** — the same torrent offered by two addons survives as two entries. 
- **Ranking:** `addonRanked` flag feeds `harbor-core` (Rust `scoring.ts`) for aiostreams; other addons are ranked by addon order (`streams/scoring.ts`, `harbor-core/src/*`).

### 3.2 Catalogs (`catalog`)

- **Home rows:** `src/lib/addons.ts:253-347` `loadAddonRows()` — merges Stremio-account addons + locally-installed addons (`gatherCatalogAddons`, dedup by transportUrl; local entries with missing manifest are re-fetched). For every catalog def (skipping type `addon_catalog`), URL is `{base}/catalog/{type}/{id}.json`, or with `/{name}={value}&…}.json` when the catalog declares required extras — required `search` extra is skipped (returns null), and each required extra uses its **first option** (`requiredCatalogExtras`, lines 270-288). All requests fire in parallel, **8 s timeout**, failures → row dropped. Rows deduped by normalized `name::type` (strips "movies/movie/series/shows/show/tv shows/tv"), capped at 24 rows (200 without dedup).
- **Pagination:** `fetchAddonCatalogPage` appends `skip=<n>` (`addons.ts:360-379`); `createAddonCatalogFetcher` learns the page size from the first response (lines 381-395).
- **Search:** `src/lib/search-addons.ts:17-62` — targets catalogs of type movie/series that declare a `search` extra (max 12 catalogs), URL `{base}/catalog/{type}/{id}/search=<q>.json`, `Promise.allSettled`, cap 20 per catalog; grouped variant `searchAddonGroups` (max 8 addons × 6 catalogs, 14 metas each).
- **Cache:** catalog list/rows via TanStack Query (`query/client.ts`: staleTime 5 min, gcTime 30 min, retry 1); addon directory staleTime 1 h; per-manifest staleTime 24 h (§5.3).

### 3.3 Metadata (`meta`)

- `src/lib/meta-resource.ts:23-63` `resolveMeta()`: races Cinemeta against addon metas. Collects user + local addons that accept `meta` for type/id (excluding cinemeta addons by id/url), fires all addon meta requests concurrently, **4 s timeout each** (`ADDON_TIMEOUT_MS`, line 6). If `preferCustomMetaAddon` setting is on, first addon meta **with a poster** wins; otherwise Cinemeta wins if it has a poster, else first addon result. URL: `{base}/meta/{type}/{id}.json`.
- Also `fetchAddonMeta` in `addons.ts:349-358` (8 s timeout).

### 3.4 Subtitles (`subtitles`)

- `src/lib/subtitles/providers/addons.ts` — `searchAddons()`: filters addons via `addonAccepts(a,"subtitles",type,id)`, content id = stremioId or imdbId prefixed `tt`, episode form `<id>:<season>:<episode>`; extra segment `videoHash=…&videoSize=…&filename=…` appended as `/<k=v>&…` path segment when available. URL `{base}/subtitles/{type}/{id}[<extra>].json`. All in parallel (per-addon try/catch, no timeout of its own — relies on safeFetch's 30 s ceiling, §3.6). Subtitle rows get synthesized unique ids `<addonname>-<id|idx>`, lang normalized, `source:"addon"`, format from `SubFormat`. Gated by settings flag `subProvidersEnabled.addons` (default true, `settings/defaults.ts:209`).
- OpenSubtitles official addon is also accessed via the same URL pattern through the proxy (`subtitles/providers/opensubtitles-v3.ts:32`).

### 3.5 Caching / query layer

`src/lib/query/client.ts` — one shared TanStack QueryClient: `staleTime 5 min`, `gcTime 30 min`, `retry 1`, `refetchOnWindowFocus: false`, `refetchOnReconnect: true`. Addon-catalog keys in `src/lib/query/keys.ts`: `addons.installed(authKey)` (stale 60 s), `addons.directory()` (stale 1 h), `addons.manifest(url)` (stale 24 h, retry 1). `use-idle-page-prefetch.ts` prefetches the directory on idle.

### 3.6 Transport layer (`safeFetch`)

`src/lib/safe-fetch.ts` — all addon HTTP goes through this:
- **Desktop (Tauri):** native `harbor_fetch` Rust command, **30 s hard timeout**, abortable via `harbor_fetch_cancel`; on native failure falls back to `@tauri-apps/plugin-http` when policy allows (`safe-fetch-policy.ts`).
- **Web:** Torrentio/TorBox/one workers.dev host are **direct** (Cloudflare blocks datacenter IPs); everything matching `.elfhosted.com/.strem.fun/.strem.io/.stremio.homes/.workers.dev/.vercel.app/.onrender.com/…` is rewritten to `/api-proxy/<host><path>`; `authorization` headers are converted to `x-harbor-auth` for the proxy.
- Privacy blocklist (`privacy/blocklist`) rejects tracker URLs before fetch.

### 3.7 AIOStatus special case

`src/lib/streams/aiostatus.ts` — status-only addons (family detect `addon-detect.ts`) are never polled for real streams (`streams/addons.ts:45-48`); instead Harbor reads their catalogs (skipping catalogs with required extras), then fetches `/stream/{type}/{id}.json` per service and parses debrid health (`Days left: N`, `NN%`, emoji/keyword status) into a `Map<DebridSlug, ServiceHealth>` for the debrid status UI. Fallback probe uses hardcoded `tt0111161`/`tt0944947` if catalogs yield nothing.

---

## 4. Install / uninstall / update / reorder / config flows

### 4.1 Local install store

`src/lib/addon-store.ts` — localStorage key `harbor.installed-addons`, entries `{ id, transportUrl, installedAt, manifest? }` (manifest slimmed per §2; quota overflow → strip manifests to bare ids/urls, lines 124-144). Separate `harbor.addons.disabled` set holds disabled transportUrls (client-side enable/disable only — not synced to Stremio). First-run seeding exists but `DEFAULT_ADDONS = []` (lines 10-38) — FACT: no addons are auto-installed in v0.9.21.

### 4.2 Install (from URL)

`installFromUrl(rawUrl, {replaceId?})` (`addon-store.ts:275-307`):
1. `parseAddonUrl` normalizes: trims, `stremio://` → `https://`, strips `/configure` and `/#/configure`, trailing slashes; requires http(s); appends `/manifest.json` if missing; URL-validates.
2. `fetchManifestAt` → **manifest validation**: must be a JSON object with non-empty string `id` and `name` (lines 236-242). HTTP error / invalid JSON / missing fields → typed error messages surfaced in the UI.
3. Local save: removes any existing entry with the same transportUrl (and the `replaceId` entry if given), appends `{ id: manifest.id, transportUrl, installedAt, manifest }`.
4. **Sync to Stremio account** (if auth key present): `pushToStremio` = read account addons → filter same transportUrl → append → `addonCollectionSet`. On API failure returns `false` and the install is still counted as **local-only** (UI toast: "Installed locally"). If a `replaceId` with a different id was given, the old id's addons are also removed from the account.
5. Returns `{ addon, syncedToStremio, replaced }`.

`installAddon(id, transportUrl)` (lines 264-273) is the simpler variant used by directory cards (non-configurable addons).

### 4.3 Update / re-configure (swap)

- "Manage" on an installed addon opens `AddonInstallModal` in `manage` mode (`views/addons.tsx:519-531`) or the detail page; pasting a new URL resolves the manifest and classifies the match: `fresh` | `id-match` (same manifest id) | `hostname-match` (same host as existing → `replaceId` = old id; `install-modal.tsx:60-95`).
- The modal shows staged progress: "Reading manifest → Saving to library / Swapping configuration → Syncing to Stremio" (`install-modal.tsx:103-128`), then calls `installFromUrl(url, { replaceId })`. Update = replace semantics; toast "Updated" when `replaced` is true (`views/addons.tsx:542-556`).
- Configurable addons (`behaviorHints.configurable|configurationRequired`) are not installed directly from cards — they open the detail view, whose install path renders the **InstallerViewport** (full-screen iframe of the addon's `/configure` page, `src/components/installer-viewport.tsx`), intercepts the `stremio://` link the configure page emits (postMessage / `harbor:deeplink-install` / paste), and installs the resulting manifest URL — with a Lottie "boat" install overlay (`installer-viewport/install-overlay.tsx`) and a Discord activity hint (which deliberately omits the URL if `isAdultText(url,title)` matches, `installer-viewport.tsx:108-119`). 7.5 s "won't load" fallback (blocked iframe) with open-in-browser escape hatch. On Linux, the iframe approach is replaced by the native Harbor Browser window (`installer-viewport.tsx:19-32` + `src-tauri/src/browser.rs:113-125` captures `stremio://`/`manifest.json` navigations).

### 4.4 Uninstall

`uninstallAddon(id, transportUrl?)` (`addon-store.ts:309-332`): remove from local store, purge its disabled-flag, and (if signed in) remove matching transportUrl (or manifest id) entries from the Stremio account via `addonCollectionSet`. Account failures are swallowed (`.catch(() => {})`) — local removal always succeeds.

### 4.5 Reorder (critical-path safety design)

`src/lib/addons-store/reorder.ts` — the most defensively written module in the system:
- Local-only display order stored at `harbor.addonOrder` (url sequence); applies to UI listing only.
- Account-level reorder `saveCollectionOrder(authKey, baseline, next, alreadyBackedUp, onStep)` runs a **5-stage protocol**: (1) validate — non-empty, same length, every item has a transportUrl, identical URL multiset, bijective JSON item match; (2) re-fetch account addons and abort with `stale` if the collection drifted; (3) push a backup snapshot (max 5, `harbor.addonOrderBackups`; falls back to slim URL/name-only snapshots on quota pressure); (4) `setUserAddonsRaw` write; (5) read-back verification — URL sequence must equal what was written, else `verify` failure with current state.
- `views/addons.tsx:566-583` toast distinguishes "Addon order synced to your Stremio account" (cloud scope) vs "Addon order saved on this device".
- Restore UI in `views/addons/organize/backups-card.tsx`.

### 4.6 Change propagation

Every successful install/uninstall/reorder dispatches the DOM event `harbor:addons-changed`; the catalog store listens and invalidates only the cheap `addons.installed` query (`addons-store/store.ts:308-314`) — the directory pipeline (40+ manifests) is not refetched.

---

## 5. Addon discovery store

### 5.1 Primary directory — stremio-addons.net REST API

`src/lib/providers/stremio-addons.ts` — base `https://stremio-addons.net/api/v0`:
- `listAddons(params)` → `GET /api/v0/addons?page&limit&search&nsfw=only|exclude&category[]&sort_by=createdAt|stars&order=asc|desc&after`. Response `{ addons: SAAddon[], pagination: {page,limit,total,totalPages,hasNextPage,hasPreviousPage} }`.
- `SAAddon` carries `uuid, url, manifestUrl, manifest, slug, stars, categories[{name,slug}], configureUrl, createdAt, updatedAt, documentation?` — i.e. **manifest embedded**, plus community star rating.
- `getAddon(uuidOrSlug)` → `/api/v0/addons/:id` returns `SAAddon & { instances: SAAddon[] }` (other instances of the same addon).
- `listCategories()` → `/api/v0/categories`; 16-entry hardcoded fallback list (anime, asian drama, bollywood, debrid support, http streams, live tv, metadata, misc, movies, music, nsfw, radios, subtitles, torrents, tv shows, usenet) when the API fails (`stremio-addons.ts:280-297`).
- `listRising()` → `/api/v0/rising` returns `{ addons: SAAddon & { recentStars }[] }` — "Top rising: most starred in 24 hours" (`views/addons.tsx:64`).
- Browse modes: `top` (stars desc), `rising` (recentStars), `new` (createdAt desc) (`views/addons.tsx:55-66`, `browse-pane.tsx`).
- **Caching:** in-memory Map, TTL 1 h, max 48 entries; registered with the memory-maintenance eviction system (`registerEvictable("stremio-addons-list")`).
- **Fallback:** any API failure → `loadFallbackAddons()` = Stremio's official/community catalogs (§5.2), converted to SAAddon shape (stars 0), with client-side search/nsfw/sort/pagination emulation (`applyListParams`). Merging also enriches API results: community addons not present in the API response and matching filters are appended and counted into `pagination.total` (`stremio-addons.ts:205-241`).

### 5.2 Stremio community/official catalogs

`src/lib/addons-store/community.ts`:
- `https://v3-cinemeta.strem.io/addon_catalog/all/community.json`
- `https://v3-cinemeta.strem.io/addon_catalog/all/official.json`
- `https://api.strem.io/addonsofficialcollection.json` (flat official collection; accepts array or `{addons:[]}`)
All three fetched in parallel; failures silently contribute `[]`; deduped by manifest id. Used as (a) fallback for the SA API, (b) enrichment of the SA list, (c) a direct source in the directory merge.

### 5.3 Catalog merge & rails (directory pipeline)

`src/lib/addons-store/store.ts`:
- `mergeBaseCatalog(local, stremioAccount, community, saList)` builds one map keyed by manifest id with source tags `curated | community | stremio-user | harbor-local`. transportUrl collision re-keys entries to the real manifest id (lines 111-127).
- Curated entries (`CURATED_ADDONS`, `curated.ts`) — **FACT: the curated list and curated rails are EMPTY in v0.9.21** (`curated.ts:49-51`: `CURATED_RAILS = []`, `CURATED_ADDONS = []`). The whole curation/recommendation/hero/rail tiering machinery (`heroEntry`, `buildRail` tiers by `recommended`, `relatedAddons`, `recommendedAddons`) exists and runs against an empty dataset. INFERENCE: curation is seeded at build time in release pipelines (the file is committed empty in this snapshot), or the feature ships dormant.
- Directory query: SA list `{ limit: 200, sort_by: "stars", order: "desc" }` + community, stale 1 h. Curated entries without a directory manifest are fetched individually (`fetchManifest`, stale 24 h, retry 1) — first paint never blocks on them.
- `finalizeCatalog`: rekey by real manifest id; enrich name/logo/description/background from SA manifests; **normalized-name dedupe** (strips `[brackets]`, `|suffix`, and `rd|tb|ad|premiumize|debrid|elfhosted|community|official|free|paid|sponsored|by X` words) — if one of a name-bucket is installed, the rest are hidden; else curated > SA-listed > first wins; always hide `org.stremio.opensubtitles` and `com.opensubtitles.v3` (Harbor ships its own OpenSubtitles handling).

### 5.4 Community index + "top movers" velocity

- `src/lib/providers/stremio-addons-index.ts` — `ensureCommunityIndex()` pages up to 6 pages × 100 addons sorted by stars, builds `byManifestId` / `bySlug` maps, TTL 1 h, single-flight with subscribers (`useCommunity` hook, `communityFor(manifestId)` used by detail rails).
- `src/lib/providers/stremio-addons-velocity.ts` — snapshots stars per uuid into `harbor.stremio-addons.velocity.v1` (max 14 snapshots, one per ≥12 h), computes `computeMovers(8)`: addons with star delta ≥ 5 since the earliest snapshot, "windowDays" = elapsed span. Powers a "movers" rail.

### 5.5 Ratings & ranking inside the UI

- Stars come **only** from stremio-addons.net (`SAAddon.stars`, `rising.recentStars`) — Harbor cannot rate; it deep-links to `https://stremio-addons.net/addons/<slug>#rate` (`rateOnSiteUrl`, `stremio-addons.ts:392-394`).
- Rail ordering in the store tiers by `curated.recommended` (90+/80+/70+), then curated, then installed, then everything else; shuffled within tiers; hard cap 16 (`buildRail`, `store.ts:434-460`).
- `relatedAddons` / `recommendedAddons` (`addons-store/recommend.ts`): similarity = category match (+50), tag overlap (+8/tag), rail overlap (+6), type overlap (+4), resource overlap (+3), curated score/20; taste boost +30 when the candidate's category matches the user's installed mix, +20 same-category-as-target, +12 curated; adult parity enforced (adult candidates only for adult targets).

### 5.6 Adult gating

- Setting `showAdultAddons` default **false** (`settings/defaults.ts:141`); toggle behind `AgeGateModal` (`views/addons.tsx:296-300, 371-392`); `nsfw` category hidden when off (`views/addons.tsx:442`).
- Classification: `isAdultAddon` = curated `nsfw` flag OR `manifest.behaviorHints.adult === true` OR keyword scan `isAdultText(id, name)` over a ~180-term substring list + ~70 word-boundary terms with leet/diacritic normalization (`addons-store/adult-filter.ts`). When adult content is off, adult addons are deleted from the catalog entirely (`store.ts:219-223`); `nsfw=exclude` also filters the SA browse list. Related addons enforce adult parity. Search in the SA API fallback honors `nsfw: "exclude"` via `behaviorHints.adult`.
- Catalog-level adult filtering for content metas uses the same matcher (`isAdultAnime`, genre whitelist `hentai|erotica`, `adult-filter.ts:244-247`).

---

## 6. Deep-link handling for addon install

`src/lib/deep-link.ts` + Rust, three platform paths:

1. **OS-level registration:** `tauri_plugin_deep_link` — Windows & Linux register on startup (`src-tauri/src/lib.rs:513-531`; Linux skipped under Flatpak, uses the packaged desktop entry). macOS registers a custom `stremio://` URI scheme protocol handler instead (`lib.rs:486-496`), emitting `harbor:stremio-deeplink` with the raw URL.
2. **Routing:** `startDeepLinkBridge()` (`deep-link.ts:98-182`) listens to `onOpenUrl` (plugin), `harbor:stremio-deeplink` (single-instance arg forwarding / macOS scheme), and `harbor://browser-stremio-capture` (Linux Harbor Browser interception, 2.5 s dedupe window, closes the browser window). For each URL: `parseStremioOpen` handles `stremio://detail/<type>/<id>/<videoId>` and `stremio.com/#/detail/...` → `harbor:deeplink-open` (media navigation). Otherwise `shouldForward()` (harbor:// scheme, `stremio://` when installer viewport open or `__harborStremioDeeplink` set, or anything containing `manifest.json`) → `emitDeepLinkInstall(rawUrl)`.
3. **Consumption:** `harbor:deeplink-install` → `InstallerViewportRoot` (if the installer viewport is open, it consumes directly and clears the pending link, `installer-viewport.tsx:201-209`) or `AddonsView` opens the `AddonInstallModal` (or consumes a pending link on mount, `views/addons.tsx:115-129`).
4. **Opt-out:** setting `stremioDeeplinkInstall` (default **true**, `settings/defaults.ts:386`; forced on for existing users on upgrade via `load.ts:123-125`) toggles OS registration through Rust `deeplink_set_stremio` / `deeplink_is_stremio_registered` (`lib.rs:88-106`). When off, `stremio://` links go to the official Stremio app; Harbor still installs anything triggered inside the app.

---

## 7. Malformed addon / partial failure handling

- **Malformed manifest at install:** `validateManifest` rejects non-objects, missing/empty `id` or `name` with specific error strings (`addon-store.ts:236-242`); non-JSON responses → "Response wasn't valid JSON…"; HTTP errors → "Manifest fetch failed (HTTP <status>)…" (`fetchManifestAt`, 244-256). Errors propagate to toasts / modal error states.
- **Directory-level:** `fetchAddonCatalog`/`fetchFlatCollection`/`fetchCommunityAddons` swallow per-source failures (`[]`); a bad community/saList addon just never enters the map. Curated manifest fetches retry once then silently render manifest-less (category falls back to "tools", `store.ts:358`).
- **Stream-level:** per-addon try/catch + per-addon timeout; `Promise.allSettled`; failures logged (`dwarn`) and dropped; partial results delivered progressively (`onPartial`). Status addons and addons with no matching id are skipped with an info log (`streams/addons.ts:64-65`).
- **Catalog rows / meta / subtitles:** per-request null/empty returns; only healthy rows render. Subtitles dedupe unique-ids prevent key collisions between addons.
- **SA API:** full fallback ladder API → community catalogs → client-side filtering; rising/categories degrade to `[]`/defaults without crashing (`stremio-addons.ts:234-241, 264-278, 331-341`).
- **Reorder:** 5-stage validation protocol with backups and read-back verification (§4.5) — the strongest anti-corruption posture in the codebase.
- **Auth:** placeholder user on failed `getUser` (accepts the key anyway); installs degrade to local-only when account sync fails; uninstall/account cleanup swallows API errors.
- **Storage:** localStorage quota overflow → manifest-stripped retry, then slim backups for order snapshots.
- **In-app installer:** iframe load timeout (7.5 s) → "won't load inside Harbor" escape hatch with paste-based fallback; install failures show error phase with Dismiss.

---

## 8. FACT vs INFERENCE

**FACT (code-verified):**
- Auth key arrives via loopback HTTP callback from `stremio.com/login` (`stremio_auth.rs`); persisted per Harbor profile in localStorage `harbor.auth.<profileId>` in plain text; 5-min web-auth timeout; server-side logout endpoint is defined but never invoked; sign-out is local-only.
- Addon collection read/write uses `addonCollectionGet` / `addonCollectionSet` on `https://api.strem.io/api`; installs sync to the account only when signed in, and degrade to local-only on failure.
- Manifest fields consumed: `id, name, version, description, logo, background, contactEmail, catalogs[], resources[], types[], idPrefixes[], behaviorHints{adult,configurable,configurationRequired}`; local copies are slimmed.
- Stream requests: parallel, no retry, 8 s/22 s per-addon timeouts, per-addon abort, progressive partial results, per-addon dedupe, Chrome-UA, `addonRanked` only for aiostreams.
- Catalogs: parallel with 8 s timeout, required-extra-first-option resolution, `skip=` pagination, `search=` for search catalogs; meta race is Cinemeta-first by default (4 s addon timeout); subtitles use `<id>:<s>:<e>` + `videoHash/videoSize/filename` extras.
- Discovery = stremio-addons.net API v0 (list/detail/categories/rising, 1 h cache) with Stremio community+official catalog fallback; curation dataset is **empty** in this snapshot; star ratings are remote-only (rate via site link).
- Deep links: OS-registered `stremio://` scheme (Windows/Linux via tauri-plugin-deep-link; macOS custom scheme handler), routed to install-modal or installer viewport; opt-out setting exists and is default-on (forced on for upgrades).
- Reorder writes to the Stremio account are guarded by validate → refetch → drift-check → backup → write → read-back-verify.

**INFERENCE (reasonable, not code-proven):**
- The auth key likely remains valid server-side after Harbor sign-out (logout endpoint unused) — the official Stremio app/other devices are unaffected.
- `CURATED_ADDONS`/`CURATED_RAILS` are probably injected at build/release time rather than shipped empty to users (all the hero/rail UI is wired to them); if shipped as-is, Discover falls back entirely to community rails.
- The stremio-addons.net API's `nsfw`/`category`/`after` parameters are honored server-side; Harbor's client-side adult filtering is a second layer, and its community-fallback adult filtering relies on `behaviorHints.adult` alone (the keyword matcher is applied in the catalog store, not in the SA fallback path) — so adult addons without the hint could appear in fallback search results when adult mode is on, and be hidden by the catalog layer regardless when off.
- 30 s safeFetch ceiling means subtitle addon requests can block a subtitle search for up to ~30 s in the worst case (no per-addon subtitle timeout).
- Stream dedupe is per-addon: cross-addon duplicates of the same torrent appear once per addon — consistent with Stremio's behavior but worth mirroring in a reimplementation.

---

## Appendix: key files index

| Concern | Files |
|---|---|
| Auth | `src-tauri/src/stremio_auth.rs`, `src/lib/stremio-auth.ts`, `src/lib/auth.tsx`, `src/lib/stremio.ts`, `src/lib/profiles.tsx`, `src/components/auth-modal/stremio-web-button.tsx` |
| Account addon CRUD | `src/lib/addons.ts` (collection API + catalog rows), `src/lib/addon-store.ts` (local store + install/uninstall/update) |
| Streams | `src/lib/streams/addons.ts`, `addon-detect.ts`, `aiostatus.ts`, `cached.ts` |
| Meta/catalog/subtitles | `src/lib/meta-resource.ts`, `src/lib/search-addons.ts`, `src/lib/subtitles/providers/addons.ts` |
| Discovery store | `src/lib/addons-store/{store,community,curated,recommend,reorder,adult-filter}.ts`, `src/lib/providers/stremio-addons*.ts` |
| Install UI | `src/components/installer-viewport.tsx`, `installer-viewport/install-overlay.tsx`, `src/views/addons.tsx`, `views/addons/{install-modal,addon-detail,organize/*,discover-pane,browse-pane,installed-pane}.tsx` |
| Deep links | `src/lib/deep-link.ts`, `src-tauri/src/lib.rs` (registration + scheme), `src-tauri/src/browser.rs` |
| Transport | `src/lib/safe-fetch.ts`, `safe-fetch-policy.ts`, `src/lib/query/*`, `src/lib/request-scheduler.ts` |
| Settings | `src/lib/settings/{defaults,types,load}.ts` (keys: `showAdultAddons`, `stremioDeeplinkInstall`, `preferCustomMetaAddon`, `subProvidersEnabled.addons`) |
| Ad reports | `src/lib/ad-report/{submit,window}.ts` (reports ad breaks in addon streams to `bugs.harbor.site/v1/adreport`, only for `ih_`/`rg_`-sourced streams) |
