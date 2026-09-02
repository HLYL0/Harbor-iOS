# Harbor v0.9.21 — Forensic Report: METADATA + ANIME Subsystems

> Source: `C:/Users/Admin/AppData/Local/Temp/harbor-ref` (git checkout of Harbor, a cross-platform Stremio client: Tauri 2 + React/TS + Rust/libmpv).
> Scope: `src/lib/providers/**`, `src/lib/anilist/**`, `src/lib/mal/**`, `src/lib/awards/**`, `src/lib/anime-awards.ts`, `src/lib/discover/**`, `src/lib/catalog-page/**`, `src/lib/lists/**`, `src/lib/wrapped/**`, `src/lib/trakt/**`, `src/lib/stremboxd/**`, `src/lib/simkl/**`, `src/lib/skip-intro/**`, `src/components/anilist|mal|letterboxd|anime-hero`, plus award/badge components.
> Notation: **FACT** = verified in code. **INFERENCE** = deduced from code but not directly observed.

---

## 1. Provider inventory (endpoints, keys, consumed fields, UI feed)

### 1.1 Cinemeta (Stremio's official catalog addon)
- **Files:** `src/lib/providers/cinemeta-details.ts`, `cinemeta-rating.ts`, `src/lib/cinemeta.ts` (catalog functions).
- **Endpoint:** `https://v3-cinemeta.strem.io` — `meta/{movie|series}/{imdbId}.json`, genre feeds (`topMovies`/`topSeries`). No API key.
- **Consumed:** `imdb_id`, `moviedb_id`, `name`, `cast[]`, `director[]`, `writer[]`, `country`, `description`, `releaseInfo`, `runtime`, `imdbRating`, `logo/poster/background`, `genre[]`, `trailerStreams[]`, `videos[]` (season/episode/thumbs).
- **UI feed:**
  - Default catalog source when no TMDB key (top movies/series by genre).
  - `cinemetaDetails()` → fallback `TmdbDetail` (cast, directors, writers, genres, trailers, "similar" from genre feeds) for IMDb-id metas when TMDB unavailable (`cinemeta-details.ts:147`).
  - `cinemetaRatingPrefetch/useCinemetaRating` → cheap IMDb rating on cards.
  - **Anime:** episode-thumbnail fallback (`enrichCinemetaThumbs` in `anime-episode-enrich.ts:21`); metahub episode stills URL `https://episodes.metahub.space/{imdb}/1/{abs}/w780.jpg` (`anime-detail.ts:371`).
- **Budget/limits:** none.

### 1.2 TMDB (primary metadata provider)
- **Files:** `src/lib/providers/tmdb.ts` (barrel), `tmdb/tmdb-client.ts`, `tmdb-details.ts`, `tmdb-people.ts`, `tmdb-keywords.ts`, `tmdb-images.ts`, `tmdb-trailers.ts`, `tmdb-catalogs.ts`, `tmdb-critic.ts`, `tmdb-watch.ts`, `tmdb-imdb-resolve.ts`, `tmdb-calendar.ts`, `tmdb-collection.ts`, `tmdb-episode-groups.ts`, `tmdb-episode-details.ts`, `tmdb-episode-types.ts`, `tmdb-episode-cache.ts`, `tmdb-anime.ts`, `tmdb-lite.ts`, `tmdb-meta-mappers.ts`, `tmdb-image-lang.ts`.
- **Endpoint:** `https://api.themoviedb.org/3` (user-supplied `settings.tmdbKey`), images `https://image.tmdb.org/t/p`. Scheduler: 6 concurrent, retry ×4 with backoff, 429/5xx pause, gzip auto-decompress (`tmdb-client.ts`).
- **Key calls:**
  | Call | Path | Purpose / UI feed |
  |---|---|---|
  | `tmdbDetails` | `{movie|tv}/{id}` + `append_to_response=credits,aggregate_credits,recommendations,similar,videos,external_ids,images,keywords,translations` | Detail page: cast/crew/directors/writers/creators/producers/composer/cinematography/editor, genres, spoken langs, countries, companies, networks, trailer + extra YouTube videos, gallery (backdrops/posters/logos), recommendations/similar rails, seasons, budget/revenue, homepage, `external_ids.imdb_id` |
  | `find/{imdb}` `external_source=imdb_id` | tt→TMDB id resolution (bidirectional, cached, `tmdb-imdb-resolve.ts`) |
  | `movie/{popular|top_rated|now_playing|upcoming}`, `tv/{popular|top_rated|airing_today|on_the_air}`, `trending/{type}/{window}`, `discover/{type}` | Catalog rows for Movies/Shows/Kids pages (`tmdb-catalogs.ts`) |
  | `discover/{movie|tv}` + `with_watch_providers`, `watch_region`, `with_watch_monetization_types=flatrate`, `vote_count.gte=300` | Per-service home rows (Netflix, Disney+, Hulu, Prime, Apple TV+, Max, Paramount+, Peacock, Crunchyroll — provider id map in `streaming.ts:19`) |
  | `{kind}/{id}/watch/providers` | "Stream on" badges on detail (flatrate+free+ads, region-aware, max 8) — `tmdb-watch.ts` |
  | `{kind}/{id}` + `append_to_response=credits,reviews` | **Critics' Pick**: top 6 critic reviews (author, rating, content, url), cast, key crew (`tmdb-critic.ts`) |
  | `search/multi`, `search/person` | Awards page seed→TMDB resolution (`award-page.ts`) |
  | `search/{movie|tv}` w/ year filter + scoring | Anime title/year → TMDB match for logos/backdrops (`tmdb-anime.ts:117`) |
  | `person/{id}` (+ credits) | Person pages: filmography credits, bio (`tmdb-people.ts`) |
  | `keyword/{id}` / keyword search | Keyword resolution (`tmdb-keywords.ts`) — used by discover profile + picker |
  | `find/{tt}` → `tv/{id}` → `tv/{id}/season/{n}` | Personal release calendar (upcoming episodes) — `tmdb-calendar.ts` |
  | `collection/{id}`, `search/collection` | Collections detail + "More collections" feed (`tmdb-collection.ts`) |
  | `tv/{id}/episode_groups` (type=5 only), `tv/episode_group/{id}` | **Story arcs** (anime arc grouping UI) — `tmdb-episode-groups.ts` |
  | `tv/{id}/season/{s}/episode/{e}` + credits,images,external_ids | Episode detail sheet: guest stars, crew, stills, per-episode IMDb id (`tmdb-episode-details.ts`) |
  | `tv/{id}/season/{n}` | Season episode list w/ votes (`tmdbSeasonEpisodes`) |
  | `{kind}/{id}` (lite) | Cheap card meta for wrapped/hydration (`tmdb-lite.ts`) |
- **Key fields consumed:** everything in `TmdbDetail` (`tmdb-details.ts:62-116`) — notably `vote_average` (rating), `vote_count`, `external_ids.imdb_id` (feeds OMDB/MDBList/harbor-imdb), `genre_ids` + genre map (`tmdb-meta-mappers.ts`), `original_language` (image-lang ranking, `tmdb-image-lang.ts`), `translations` (EN fallback when `translateDescriptions=false`).
- **Auth/budget:** user key only; 401/429 handled with console warnings.

### 1.3 OMDB
- **Files:** `src/lib/providers/omdb.ts`.
- **Endpoint:** `https://www.omdbapi.com/?i={tt}&apikey={key}` (+ `&Season={n}` for per-season episode ratings).
- **Consumed:** `imdbRating`, `imdbVotes`, `Ratings[]` (Rotten Tomatoes, Metacritic), `Awards` string (regex-parsed: Oscars/Emmy/BAFTA/Golden Globe wins+noms+totals), `Episodes[].imdbRating`.
- **UI feed:** RT critic %, Metascore, IMDb rating/votes on cards & detail; **Certified Fresh** (RT≥75% AND IMDb votes≥50k — `omdb.ts:345`); award counts; per-episode IMDb ratings (for normal TV).
- **Budget system (FACT, notable):** daily budget persisted to localStorage (`harbor.omdb.budget`, default limit 1000/day, UTC-midnight reset), 90% prefetch threshold, negative-miss cache (24h), 90-day data staleness, 401→keyInvalid, limit error→exhausted. React hooks `useOmdbScores`/`useOmdbBudget`.

### 1.4 RPDB (Rated Poster DB)
- **File:** `src/lib/providers/rpdb.ts`.
- **Endpoints:** default `https://api.ratingposterdb.com/{key}/imdb|tmdb|tvdb/poster-default/{id}.jpg?fallback=true`; also supports custom `posterBaseUrl` templates (`{imdbId}{tmdbId}{tvdbId}{type}{id}`), `btttr.cc` (betterposters), postersplus/elfhosted (`?tmdb_id=&imdb_id=&type=`).
- **Consumed:** nothing (pure URL builder). Poster overlays show IMDb/RT/Metacritic ratings rendered into posters.
- **UI feed:** poster images on cards/detail when configured; `needsImdbForPoster`/`needsTmdbForPoster` drive ID resolution pre-fetch.

### 1.5 Fanart.tv
- **File:** `src/lib/providers/fanart.ts`.
- **Endpoint:** `https://webservice.fanart.tv/v3/movies/{tmdbId}` / `.../tv/{tvdbId}?api_key={fanartKey}`.
- **Consumed:** hdmovielogo/movielogo, movieposter, moviebackground, moviethumb, moviebanner (movies); hdtvlogo/clearlogo, tvposter, showbackground, tvthumb, tvbanner (TV). Ranked by lang (en > 00) + likes.
- **UI feed:** logos, backdrops, posters, banners on detail; used by the anime pipeline (see §2.4).

### 1.6 MDBList (aggregated community scores)
- **Files:** `src/lib/providers/mdblist.ts`, `mdblist-batch.ts`.
- **Endpoints:** `https://api.mdblist.com/imdb/{movie|show}/{tt}?apikey=` (primary), legacy `https://mdblist.com/api/?apikey=&i={tt}`; batch `https://api.mdblist.com/imdb/{kind}/?apikey=` (card-score batching, ≤100 ids/queue, 24h TTL, 10-min backoff on failure, LS cap 1500 — `mdblist-batch.ts`).
- **Consumed:** `ratings[].{source,value}` → letterboxd, trakt, metacritic, tomatoesaudience/popcorn (RT audience), simkl, aggregate `score`.
- **UI feed:** card badges (Letterboxd %, Trakt %, Metacritic, RT audience) — `CardScores`; detail-page score chips; the ONLY source of Letterboxd/Trakt numeric ratings.

### 1.7 Harbor IMDb proxy (first-party)
- **File:** `src/lib/providers/harbor-imdb.ts`.
- **Endpoint:** `https://harbor.site/api/imdb/{episodes|title|parental}/{tt}` (keyless).
- **Consumed:** `ratings{"S:E": n}` (episode ratings), `rating` (title), `categories[{category,severity}]` (parental guide: sex/violence/profanity etc.).
- **UI feed:** **anime** per-episode IMDb ratings (`enrichHarborImdb`, `anime-episode-enrich.ts:79`, sets `ratingIsImdb`); parental guide panel; IMDb title rating fallback.

### 1.8 IMDbAPI.dev (alternative IMDb data)
- **File:** `src/lib/providers/imdbapi/imdbapi-details.ts`.
- **Endpoint:** `https://api.imdbapi.dev/titles/{tt}` (+ `/episodes`, `/credits`, per-episode title).
- **Consumed:** `primaryTitle`, `primaryImage`, `startYear`, `runtimeSeconds`, `genres`, `rating{aggregateRating,voteCount}`, `plot`, `directors/writers/stars[]`.
- **UI feed:** fallback detail (cast/directors/writers/runtime/genres) when TMDB/Cinemeta miss.

### 1.9 Wikidata SPARQL (non-anime awards)
- **File:** `src/lib/providers/wikidata.ts`.
- **Endpoint:** `https://query.wikidata.org/sparql` (POST-style GET, `format=json`, LIMIT 400).
- **Queries:** films via `wdt:P345` (IMDb id); wins via `p:P166/ps:P166` (+`pq:P585` date, `pq:P642` category, `pq:P1686` work), nominations via `p:P1411/ps:P1411`; union with recipient-inverse pattern.
- **Consumed:** award label, category label, recipient, date, work + work IMDb id; classified into `AwardType` (oscar, emmy, golden_globe, bafta, sag, critics_choice, cannes, venice, berlin, other) via category-prefix matching.
- **UI feed:** per-title won/nominated award entries on detail (`harbor.awards.wikidata.v10` cache, 30d stale).

### 1.10 TVDB
- **Files:** `src/lib/providers/tvdb.ts`, `tvdb-proxy.ts`, `tvdb-order.ts`, `tvdb-order-cache.ts`.
- **Endpoints:** `https://api4.thetvdb.com/v4` (POST `/login` {apikey}→token, 23h token cache), or keyless proxy `https://harbor.site/api/tvdb/v4{path}`; artwork `https://artworks.thetvdb.com...`; image/artwork proxies `https://harbor.site/api/tvdb/{images|artwork}` (`tvdb-proxy.ts`).
- **Consumed:** series search/id, episode lists (number, season, absoluteNumber, image, imdbId), series meta, alternate episode **orderings** (official/absolute/etc. cached per series+seasonType).
- **UI feed:** **anime episode thumbnails** (`fetchTvdbThumbs`, season+absolute indexes — `anime-tvdb-thumbs.ts`); episode ordering for series; artwork fallbacks.

### 1.11 TVMaze
- **File:** `src/lib/providers/tvmaze.ts`.
- **Endpoint:** `https://api.tvmaze.com/lookup/shows?imdb={tt}` (+ episodes).
- **Consumed:** show id/name/image, `isAnime` flag (genre/genre-network detection), episodes (season, number, name, airdate, image, summary).
- **UI feed:** anime-detection signal + episode data used by calendar/continue logic. (RSS/episode sources used by `src/lib/calendar-sources.ts`.)

### 1.12 Streaming services catalog (`streaming.ts`)
- **FACT:** hardcoded provider-id map: Netflix 8, Disney+ 337, Hulu 15, Prime 9+119, Apple TV+ 350, Max 1899+384, Paramount+ 531/582/1715/1854, Peacock 386+387, Crunchyroll 283. Per-service TMDB `discover` rows (12 movies + 12 series interleaved, `vote_count.gte=300`, flatrate-only, region from settings) → "Streaming" home rows. `serviceBadge()` supplies logo/tint for badges. No separate API — reuses TMDB key.

### 1.13 Stremio addons directory (not content metadata, but in providers dir)
- **Files:** `src/lib/providers/stremio-addons.ts` (`https://stremio-addons.net/api/v0`), `stremio-addons-index.ts` (community index), `stremio-addons-velocity.ts` (popularity snapshots → "top movers"), `addon-logo-prefetch.ts`.
- **UI feed:** addon discovery/catalog/rising/velocity on the Addons page.

---

## 2. ANIME pipeline (Kitsu → AniZip → TMDB, MAL, episodes, dub/sub, AniSkip, Anime4K, awards)

### 2.1 ID normalization — everything becomes a Kitsu id
`src/lib/providers/anime-mapping.ts` is the hub:
- `parseKitsuId("kitsu:123")` → 123.
- `externalToKitsu(source, id)` — ARM (`https://relations.yuna.moe/api/ids?source={mal|anilist|anidb|...}&id=`) → kitsu id. Persisted 30d (negative 24h) in localStorage `harbor.extkitsucache`.
- ARM also powers `armFromKitsu` → {mal, anidb, anilist}.
- **Fallback ladder (FACT):** AniZip first, then ARM→anidb→`anime-lists` XML.
  - `kitsuToTvdb`: AniZip `mappings.thetvdb_id` → ARM→anidb→`anime-list-master.xml` (`raw.githubusercontent.com/Anime-Lists/anime-lists`, regex-parsed anidb→tvdb / anidb→imdb, 7-day LS cache).
  - `kitsuToImdb`, `kitsuToAnidb`, `kitsuToAnilist`, `kitsuToMal` — same ladder (AniZip `mappings.*`, ARM, XML).
  - `anilistToMal` / `anidbToMal` — ARM then AniZip.
  - `imdbToKitsu(tt)` — AniZip by imdb → ARM by anidb → XML imdb→anidb index → ARM.
  - `tmdbTvToKitsu(tmdbId)` — AniZip by themoviedb_id → ARM by anidb.
- **Side-entry promotion (FACT):** `preferMainTv()` — for OVA/ONA/special/music entries, walks Kitsu media-relationships to the main TV series (highest episodeCount) so sequels resolve to the parent show (`anime-mapping.ts:6`, `kitsu.ts:454` `kitsuMainTvSeries`).

### 2.2 AniZip (`src/lib/providers/anizip.ts`)
- `https://api.ani.zip/mappings?{kitsu_id|mal_id|anilist_id|anidb_id|imdb_id|themoviedb_id}=`
- Client-side queue with 90ms gap, 4s timeout, inflight dedupe, unlimited TTL cache.
- Consumed: cross-DB id map (`mappings.*`), per-episode `titles{en,x-jat,ja}`, `overview`, `image`, `airDate`, `runtime`, `filler`, `absoluteEpisodeNumber`, `tvdbId`, `rating`, `seasonNumber/episodeNumber`, `finaleType`.
- `pickEpisodeTitle`: en → x-jat → ja.

### 2.3 Kitsu (`src/lib/providers/kitsu.ts`) — canonical anime metadata
`https://kitsu.io/api/edge` (JSON:API, no key, 30-min TTL, evictable):
- `/anime/{id}?include=genres,categories` → title (en>canonical>en_jp), synopsis, poster/cover, averageRating (÷10), episodeCount/Length, status, subtype, dates, ageRating(+Guide), youtubeVideoId (trailer), popularityRank/ratingRank, genres+slugs, categories.
- `/anime/{id}/episodes?sort=number` (paged ×20 up to 100) → number, seasonNumber, title, synopsis, thumbnail, airdate, length.
- `/anime/{id}/anime-characters?include=character,castings.person&sort=role` (limit 30) → characters + **JA voice actors** (prefers locale `ja` casting, falls back to any).
- `/anime/{id}/media-relationships?include=destination` → related titles (role: sequel/prequel/parent_story/...).
- `/anime/{id}/anime-productions?include=producer` → studios + role (studio/production/licensor).
- `/anime/{id}/streaming-links?include=streamer` → `{url, service, subs[], dubs[]}` — legal streaming links + **sub/dub language lists**.
- `/anime/{id}/mappings` (used by AniSkip's `kitsuToMal`, `skip-intro/aniskip.ts:58`) → externalSite=myanimelist/anime.
- `kitsuSimilarByGenres` (filter genres, sort=-userCount, ageRating filter when adult hidden) → "similar" pool.

### 2.4 `animeDetails()` orchestration (`src/lib/providers/anime-detail.ts:312`)
Single entry point that builds the anime detail page:
1. Resolve kitsu id (direct or via external prefixes mal:/anilist:/anidb:).
2. `Promise.all([kitsuAnime(id), animeKitsuMeta("kitsu:id")])` — Kitsu + the **anime-kitsu.strem.fun** Stremio addon (`anime-kitsu-addon.ts`, 6h TTL; meta JSON incl. `videos[]` with `imdb_id`, `imdbSeason`, `imdbEpisode` — the playable episode ids).
3. Franchise build (see 2.6).
4. Parallel fetch: Kitsu episodes(100), characters(30), related, studios, streaming links, genre-similar (34), AniZip, AniList recommendations (via `kitsuToAnilist`).
5. **Episodes** = `buildKitsuEpisodes(addonMeta, kitsuRaw)` (addon videos authoritative; falls back to Kitsu) then `mergeAniZipEpisodes` (fills titles/overview/image/airdate/runtime/filler/absoluteNumber/tvdbEpisodeId/rating + **imdb season/episode mapping** — `anime-episode-build.ts`).
6. `seriesImdb` = AniZip `mappings.imdb_id` → episode `imdbId` → `kitsuToImdb`. If tt: every episode gets metahub thumbnail fallback (`episodes.metahub.space/{imdb}/1/{abs}/w780.jpg`).
7. Detail object: Kitsu fields into `TmdbDetail` shape (status labels: Currently Airing/Finished/TBA/Unreleased/Upcoming; networks = streamer service names; productionCompanies = studios ranked studio>production>licensor; cast = characters with VA names as "character"; recommendations/similar split 14/14 from AniList recs + Kitsu genre-similar, deduped by id+name and franchise membership).
8. `enrichEpisodes` (§2.5) + `extrasPromise` (§2.7), cast franchise cache.

### 2.5 Episode enrichment (`src/lib/providers/anime-episode-enrich.ts`)
- `enrichFiller`: kitsu→mal → `fillerEpisodes(malId)` (`src/lib/anime-fillers.ts`) → marks filler on absolute numbers.
- `enrichHarborImdb`: harbor.site IMDb per-episode ratings (`ratingIsImdb` flag).
- `enrichCinemetaThumbs` then `enrichTvdbThumbs`: thumbnail fallbacks keyed `S:E` and absolute number (TVDB prefers absolute episode list).

### 2.6 Franchise / season mapping
- **Kitsu walk** (`anime-detail.ts:134` `buildFranchise`): roles sequel/prequel/parent_story, BFS depth ≤3; entries merged with **AniList relations graph** (`src/lib/anilist/relations.ts`: SEQUEL/PREQUEL/PARENT/SIDE_STORY, depth ≤6, ≤40 nodes); both merged by normalized title keys (`norm()` strips "Season N/Part N/Cour/Nth/II..VIII" markers, ou→o normalization); foreign ids (anilist:/mal:/anidb:) re-resolved to kitsu via ARM; sorted by start date; scored (current=1000, kitsu=+4, has date=+2, has eps=+1) to pick best meta per title.
- `franchiseTags()` → per-season `S1..Sn` / movie "MOV" chips; `isFranchiseExtra` (movies, ONA/OVA/special/music, 1-episode non-airing).
- **Franchise root** (`anime-franchise-root.ts`): walks `prequel` relationships upward (≤8) to canonical root — used for continue-watching grouping (`prefetchFranchiseRoot`).
- **Playable episode filter** (`anime-franchise-episodes.ts:8`): episode is playable iff addon `streamId` present OR has `imdbId`+`imdbSeason`+`imdbEpisode`.
- **Derived formats:** `anime-format.ts` — SPECIAL/OVA/ONA/MUSIC flagged as derived (hide from continue-watching by default).
- **Jikan franchise key** (`jikan.ts:117-133`): regex strips "1st/2nd/Final Season|Cour|Part|Season N|S2|II..X" — shared keying for award matching and catalog dedupe (groups seasons to franchise anchors, oldest year wins).

### 2.7 TMDB/Fanart overlay (`extrasPromise`, `anime-detail.ts:449`)
- Requires `settings.tmdbKey`: `tmdbAnimeMatch(title, year, kind)` → search TV (and movie), scoring = exact/prefix/inclusion + origin JP +25 + genre-16 (Animation) +15 + year ±1 +20/8 + log(popularity); then `{kind}/{id}/images` → logo + backdrop.
- Fanart: movie→`fanartMovie(tmdbId)`; tv→`fanartTv(tvdbId)` (tvdbId via `kitsuToTvdb`).
- TMDB full details fetched and **year-guarded** (|Δyear|≤1) before overlay (crew/directors/writers/keywords/gallery/backdrops/logos). Cast falls back to TMDB cast when Kitsu cast empty; franchise-wide cast cache (`FRANCHISE_CAST_CACHE`).

### 2.8 Dub / Sub detection
- **Legal links:** Kitsu streaming-links `subs[]`/`dubs[]` per service; streamer badge branding in `anime-streamer.ts` (Crunchyroll/Funimation/Netflix/Hulu/HiDive/Prime/Disney/YouTube/VRV/Tubi/Hoopla/Kanopy/Apple/Max — local SVG logos + brand tints).
- **DUB badge:** `anime-dub-sub.ts` — community dub-schedule feed `https://raw.githubusercontent.com/RockinChaos/AniSchedule/master/raw/dub-schedule.json` → in-memory sets of MAL + AniList ids; `animeHasDub(metaId)` (only `mal:`/`anilist:` ids checked); badge on cards gated by `settings.showDubBadge` (`components/pick-card.tsx:117-121`). Feed is fetched lazily once, silently fails.

### 2.9 AniSkip (skip intro/outro/recap)
`src/lib/skip-intro/aniskip.ts`:
- `kitsuToMal` ladder: SIMKL local mapping cache (`src/lib/simkl/activities` kitsu→simkl→mal) → Kitsu `/mappings` endpoint; LS cache `harbor.kitsu-to-mal.cache.v1`.
- `https://api.aniskip.com/v2/skip-times/{malId}/{episode}?types=op&types=ed&types=mixed-op&types=mixed-ed&types=recap&episodeLength={sec}` → segments mapped to intro/outro/recap (`source:"aniskip"`), sorted by start; in-memory cache keyed malId:episode:length.

### 2.10 Anime4K
- **FACT — playback feature, not metadata:** `anime4kMode` setting (off/A/B/C… shader presets) flows through `components/player/transport.tsx` → mpv (libmpv); `anime4kAvailable` indicates shader availability; `components/player/anime4k-indicator.tsx` shows the "Anime4K" chip. Configured in `views/settings/quality-panel.tsx`.

### 2.11 Anime award badges (Crunchyroll / TAAF / JMAF / r-anime / Animation Kobe)
- **Data:** static bundled JSON datasets in `src/data/`: `crunchyroll-awards.json`, `taaf-awards.json`, `japan-media-arts-awards.json`, `animation-kobe-awards.json`, `r-anime-awards.json`.
- **Logic:** `src/lib/anime-awards.ts`:
  - `AwardSourceId = crunchyroll | taaf | jmaf | r_anime | animation_kobe`; prestige 100/95/90/70/60.
  - AOTY category keys: crunchyroll/taaf/r_anime `anime_of_the_year`, jmaf `grand_prize`, kobe `best_film|best_tv`.
  - Winners indexed by `awardFranchiseKey(title)` (Jikan franchise-strip + sequel-number strip + suffix strip).
  - `findAnyAwardWins(name, releaseYear)` / `findTopAward` / `groupWinsBySource` — with release-year gating (drop wins if no win is ≥ releaseYear−1) and a **synonym map** (`harbor.anime_awards.metas.v6` LS cache rebuilt from resolved metas, live-updated via `storage` events).
  - Award title → Meta resolution: `src/lib/use-crunchyroll-award-metas.ts` — for every unique winning franchise, `jikanSearchByTitle(query,10)`, match by franchise key, prefer exact (non-sequel-stripped) or earliest-year hit; cached per franchise key (negative cached too).
- **Rendering (FACT):** `components/anime-awards-block.tsx` (detail-page award section with per-source icons + AOTY star), `components/meta-awards-corner.tsx` (detail corner badge), `components/pick-card.tsx:893-944` (card badges; TAAF+Kobe/JMAF special badge styles), `components/top-rank-card.tsx`, `components/anime-hero.tsx:297` (hero award chip; Kobe icon inverted), `components/icons/award-logo.tsx` (generic award icon; anime category keys fall back to Crunchyroll icon), award rows in `views/anime.tsx:427-458` ("Award Winning Anime" row) and `views/anime-award.tsx` (per-source award browser with brand colors: TAAF #e91e63, JMAF #c41e3a, r/anime #ff4500, Kobe #8a6a3b).

### 2.12 Jikan/MAL catalog rows (`src/lib/providers/jikan.ts`)
- `https://api.jikan.moe/v4`, client throttle ≥400ms/req, 429 backoff ×4, 12s timeout, 6h LS-persisted catalog cache (top 40 queries), adult filter (`sfw=true`, Rx/Hentai/Erotica/title heuristics).
- Rows: `jikanAiringNow`, `jikanUpcoming`, `jikanTopAnime`, `jikanTopAiring`, `jikanTopPopular`, `jikanTopMovies`, `jikanTopTv`, `jikanNewReleases` (airing, start_date desc, score≥6), `jikanByGenre` (16 genres, score desc, ≥7), `jikanByEra` (date range, ≥7.5), `jikanUnderratedGems` (members asc, score≥7.8, scored_by≥4000, members<350k, sequels excluded), `jikanSearchByTitle`, `jikanRecommendationsForMalId`.
- Each result: ARM lookup → prefer `kitsu:{id}` else `mal:{id}`; franchise grouping (one anchor per franchise key).

### 2.13 AniList rows & catalog (`src/lib/anilist/browse.ts`)
- `fetchAnilistTopAnime` (SCORE_DESC, 100), `fetchAnilistTrendingAnime` (TRENDING_DESC, 40), `anilistRecommendations` (RATING_DESC, 24), `anilistAnimeSearch`, `anilistCountriesByMalIds` (batch 50), art lookups by id/mal id. Rendered via `views/anime/anilist-top-row.tsx`, `anilist-rows.tsx` (user-list rails via `useAnilistAnimeRails`), controllable per-row hide via `settings.animeAnilistRowsHidden`.

---

## 3. Awards system (non-anime + anime)

| Layer | File | Mechanism |
|---|---|---|
| Live awards per title | `src/lib/providers/wikidata.ts` | SPARQL over Wikidata (P345=P345 imdb, P166 won, P1411 nominated, categories, dates) → `AwardEntry{type,awardName,category,recipient,result,year,workTitle,workImdb}`; LS cache v10 |
| OMDB awards | `src/lib/providers/omdb.ts:211` | `Awards` string regex → Oscar/Emmy/BAFTA/Globe win+nom counts |
| Catalog/definitions | `src/lib/awards-catalog.ts` | `AWARD_CATALOG` — 10 AwardTypes with category lists |
| History | `src/lib/awards-history.ts` | bundled winner data (imported static dataset) + per-category history + **title & person inverted indexes** (`bundledAwardsForTitle`, `bundledAwardsForPerson`), merge + dedupe utilities |
| Browse pages | `src/lib/awards/award-page.ts` | builds seeds (top films up to 300, actors 18, directors 14, writers 14 by win count) from history; resolves to real metas/persons via TMDB `search/multi` + `search/person` (year proximity + media-type match + known_for_department scoring); paginated film loading (12/batch); LS people cache |
| Anime awards | `src/lib/anime-awards.ts` + `src/data/*.json` + `use-crunchyroll-award-metas.ts` | §2.11 |
| Badge rendering | `components/meta-awards-corner.tsx`, `icons/award-logo.tsx`, `pick-card.tsx`, `top-rank-card.tsx`, `anime-hero.tsx`, `anime-awards-block.tsx` | icon per source; AOTY marked; Kobe icon `brightness-0 invert`; TAAF/Crunchyroll `invert hue-rotate-180` |

---

## 4. Discover / Critics' Pick / Personalization

### 4.1 Discover scoring (`src/lib/discover/*`)
- **Events** (`types.ts`): `open | dwell | play | watchlist | watched | vote_up | vote_down` with `ProfileSnapshot {cast[], directors[], creators[], genres[], keywords[], decade, language}` (`profile.ts` — cast top-5, TMDB person ids, genre names, keyword ids).
- **Affinity** (`affinity.ts`): exponential recency half-life **90 days**; kind weights: open 1.0, play 3.0, dwell 2.5, watchlist 4.0, watched 6.0, vote_up 5.0, vote_down −5.0; category weights: cast 1.0, directors 1.5, creators 1.5, genres 0.8, keywords 1.2, decade 0.4, language 0.3; candidate `score(profile, affinity)` = weighted avg (cast/genres/keywords via mean÷√n) + sums.
- **Store** (`store.ts`): LS `harbor.discover.v1`, max 500 events, 5s debounced persist, 90s duplicate window; `useDiscover()` exposes events/affinity/cold state; consumed by `views/discover.tsx` to rank rows.
- **Inputs required (FACT):** TMDB ids (cast/directors/creators/keywords) — so personalization quality depends on TMDB key; anime metas via `profileFromMeta` only contribute genres+decade (no cast ids).

### 4.2 Critics' Pick (`components/critics-pick.tsx` + `critics-pick/*`)
- Data: `tmdbCriticData` (6 reviews ≥120 chars, dedup authors, sorted by rating; cast 20, key crew) + OMDB scores (RT %, Metacritic, IMDb) + RPDB poster + resolved logo; random pick via `pickRandom`; UI: quotes, linked reviews, stills lightbox, cast chips, awards corner.

---

## 5. Letterboxd / AniList / MAL / Trakt / SIMKL integrations

### 5.1 Letterboxd — via Stremboxd addon (`src/lib/stremboxd/*`)
- **FACT:** no direct Letterboxd API; Harbor talks to the **Stremboxd Stremio addon backend** at `https://api.stremboxd.com` (config in `stremboxd/config.ts`; client notes in `client.ts:23-57`).
- Base64url(JSON) config `{u, c:{watchlist?,popular,top250,likedFilms?}, l:[], r}`; full mode via `POST /auth/login {username,password,totp?}` → JWT `userToken`; catalogs `/stremio/:userId/catalog/{watchlist|likedFilms|popular|top250|diary|friends|recommended}`; film relationships on `/v1/film-rating` (Bearer); quick-actions (`/action/...`) require server-signed HMAC `tok` → **read-only** in-app, links out for edits (FACT).
- Letterboxd URL attached as `meta.links` (category "Letterboxd") or `https://letterboxd.com/imdb/{tt}/` (`stremboxd/to-meta.ts`); home rails via `stremboxd/home-rails.ts`; per-row toggles (`watchlist/liked/popular/top250`) in `settings.letterboxd`.
- **Also:** Letterboxd numeric ratings on cards come from MDBList (`mdblist.ts`), not Stremboxd.
- `components/letterboxd/letterboxd-row-menu.tsx` = **row edit menu only** (move up/down/hide/show) — no data fetching.

### 5.2 AniList (`src/lib/anilist/*`)
- **Auth:** OAuth2 code + PIN redirect (`https://anilist.co/api/v2/oauth/authorize`, `.../oauth/pin`), token exchange proxied `https://bugs.harbor.site/v1/anilist/token` (`config.ts`); session in LS (`session.ts`); viewer profile/avatar (`queries.ts`, `profile.ts`).
- **GraphQL:** `https://graphql.anilist.co`; 429 retry honoring `retry-after` (capped 30s) (`client.ts`).
- **Sync:** `syncAnimeProgress` — `Media(id)` + `mediaListEntry` → `SaveMediaListEntry(mediaId, progress, status)`; auto status CURRENT (from PLANNING) when playback starts (`markAnimeWatching`); auto COMPLETED at `episodes`; sent-guard per profile (`harbor.anilist.synced.v1.{profileId}`); events → toast (`components/anilist/anilist-sync-toast.tsx`); id resolution ladder kitsu→(ARM/AniZip)→anilist or mal→`Media(idMal)` (`sync.ts:69`).
- **Lists:** `MediaListCollection` (statuses + custom lists) → "Your AniList" rails (`lists.ts`, `views/anime/anilist-rows.tsx`).
- **Watched:** `watched-map.ts`/`use-anilist-watched.ts` — per-entry progress map driving episode progress markers.
- **Avatar:** `components/anilist/anilist-avatar-sync.tsx` (profile picker).
- **Browse/franchise/art:** `browse.ts`, `relations.ts`, `to-meta.ts` (§2.6, §2.13).

### 5.3 MAL (`src/lib/mal/*`)
- **Auth:** OAuth2 PKCE **plain** verifier, `https://myanimelist.net/v1/oauth2/authorize`, redirect `https://harbor.site/mal/`, token exchange + refresh via `https://harbor.site/api/mal/token` (`config.ts`, `auth.ts`); `VITE_MAL_CLIENT_ID` env.
- **REST:** `https://api.myanimelist.net/v2` (`client.ts`; Tauri HTTP plugin on desktop; auto-refresh on 401).
- **Sync:** mirrors AniList flow — `GET /anime/{id}?fields=num_episodes,my_list_status`, `PATCH /anime/{id}/my_list_status` (`num_watched_episodes`, status watching/completed), auto `markMalWatching` from plan_to_watch; per-profile sent-guard `harbor.mal.synced.v1.{profileId}`; toast `components/mal/mal-sync-toast.tsx`.
- **Lists/mutations:** `fetchListEntry/saveListEntry/deleteListEntry` (`mutations.ts`); `malRequest` lists (`lists.ts`); id resolution kitsu→(ARM/AniZip)→anilist→`Media(idMal)`→mal or direct.
- **UI:** `components/mal/add-to-mal-button.tsx` (detail page add/status control), `mal-connect-modal.tsx`, `mal-avatar-sync.tsx`; watched map `use-mal-watched.ts`.

### 5.4 Trakt (`src/lib/trakt/*`) — metadata usage
- **Auth:** device flow (`device-auth.ts`, `trakt.tv/activate`) + PIN flow; token exchange proxies `https://harbor.site/api/trakt/{token|device-token}`; OAuth via `api.trakt.tv/oauth/token` (`config.ts`).
- **Metadata/data feeds (FACT):**
  - `history.ts` — watched history (used by **Wrapped** year-in-review, `collectWatchEvents` pulls up to 2000; also "Watched on Trakt" markers in continue-watching, `components/continue-card.tsx:315`).
  - `watchlist.ts` — "Your Trakt Watchlist" home rail (`home-rails.ts`).
  - `recommendations.ts` — `/recommendations/movies|shows?limit=40&ignore_collected=true` → home rails.
  - `calendar.ts` — `/calendars/my/shows` upcoming episodes rail.
  - `lists.ts` — custom Trakt lists as source folders (`components/source-folder-card.tsx` — `fetchTraktList` + `hydrateTraktItems`).
  - `scrobble.ts` / `scrobble-hook.ts` — start/pause/stop scrobbling during playback; `comments.ts`; `profile.ts` (avatar for profile picker); `ids.ts`/`hydrate.ts` — Trakt ids (imdb/tmdb/tvdb) → meta hydration via TMDB.
  - **Trakt rating badge:** numeric Trakt score rendered on cards comes from MDBList (`settings.showTraktBadge`, `pick-card.tsx:205`), not from the Trakt API.

### 5.5 SIMKL (`src/lib/simkl/*`)
- Tracking mirror of Trakt (session/device-auth/scrobble/watchlist/history/calendar/home-rails/activities); notable metadata hook: **kitsu↔simkl↔mal mapping cache** used by AniSkip id resolution (`skip-intro/aniskip.ts:38`) and anime home rails/up-next; anime grouping (`simkl/anime-grouping.ts`).

---

## 6. Lists system (`src/lib/lists/*`)
- `types.ts`: `ListSource = mdblist | trakt | tmdb | letterboxd | imdb | mal`; `CustomList {id,name,source,ref,addedAt}`; resolve errors (missing-key/not-found/network/unparseable). Resolvers live with each provider (e.g. `src/lib/trakt/lists.ts`, MDBList list endpoints); a pasted `letterboxd.com/username/list/slug` URL is accepted as a list ref (i18n hints + `source-folder-card.tsx`). MDBList list refs use the MDBList API key; TMDB lists use TMDB key.

---

## 7. Wrapped (Stremboxd-style year-in-review) — `src/lib/wrapped/*`
- **Sources** (`collect.ts`): Trakt history (up to 2000, when connected; else local) merged with local playback history (`src/lib/playback-history.ts`) + manually-watched library items; anime detection via id prefix (`kitsu|mal|anilist|anidb|simkl:`) and `src/lib/anime-detect.ts` (`isDetectedAnime` by id or imdb).
- **Aggregation** (`aggregate.ts`): year filter, per-title counts, daily heatmap, movies/series/anime split, estimated hours (115 min/movie, 42 min/episode), longest binge, first/last play.
- **Archetypes** (`archetype.ts`): weeb (≥50% anime), binger (≥8/day), cinephile (≥60% movies), serialist (≥60% series), explorer (≥60 titles), balanced.
- **Enrichment** (`enrich.ts`): posters+genres for top 15 — anime via `animeKitsuMeta`, `tmdb:` via `tmdbLiteMeta`, `tt` via Cinemeta meta.

---

## 8. Catalog pages (`src/lib/catalog-page/*`)
- `useCatalogPage` — shared TanStack-Query rail loader for Movies/Shows/Kids/Anime pages: hero + per-row fetchers, 5-min stale/30-min GC, prefetch (`preloadCatalogPage`), lazy "load more" merging pages into the page-1 entry (`mergeRowPage` dedupe by id, cap `maxPerRow` 30, `hasMore` = fetched ≥ minVisible 14). `CatalogPageId`: movies|shows|kids|anime|home. `scope` partitions cache per key set (e.g. `tmdbKey+region` or `"jikan"`). **Anime page scope = `jikan`** (`views/anime.tsx:100`).

---

## 9. Settings keys consumed by these subsystems (FACT)
`tmdbKey`, `omdbKey`, `mdblistKey`, `fanartKey`, `tvdbKey`, `rpdbKey` + `posterBaseUrl`, per-service `streaming{}` toggles, `region`, `translateTitles`/`translateDescriptions`, `showTraktBadge`, `showDubBadge`, `animeAnilistRowsHidden`, `letterboxd{}` row toggles, `anime4kMode` (player), adult-content hiding (`adultContentHidden` gates Kitsu/Jikan queries).

---

## 10. FACT vs INFERENCE

**FACT (verified in code):**
- All endpoints, query shapes, TTLs, and cache keys listed above (each cited by file+line where notable).
- Episode playability = anime-kitsu addon `streamId` OR complete imdb trio (`imdbId`+`imdbSeason`+`imdbEpisode`) — `anime-franchise-episodes.ts:8`.
- AniZip 90ms throttle + 4s timeout; Jikan 400ms throttle; OMDB daily budget (1000 default) with 90% prefetch cutoff.
- Award datasets are **bundled static JSON** (no runtime award API); award→meta resolution uses Jikan search, cached in `harbor.anime_awards.metas.v6`.
- Dub badge only works for `mal:`/`anilist:` meta ids; Kitsu cards get it only if the card id was already mapped to those prefixes (kitsu: ids are NOT checked — `anime-dub-sub.ts:56`).
- Letterboxd numeric ratings come from MDBList; Letterboxd list/rails integration is the Stremboxd addon (read-only statuses; writes require server-signed tokens).
- Trakt rating badge is MDBList-sourced; Trakt API itself contributes history/watchlist/recommendations/calendar/lists/scrobble.
- Personalization affinity requires TMDB person/keyword ids (profileFromMeta contributes only genre+decade for non-detail metas).

**INFERENCE (reasonable but not directly observed):**
- `harbor.site` / `bugs.harbor.site` proxies are first-party serverless functions hiding provider secrets (anilist token, mal token, trakt token, tvdb v4 key, imdb scraper); their server-side behavior (rate limits, caching) is unknown from this repo.
- `anime-kitsu.strem.fun` is the community "Anime Kitsu" Stremio addon (host name only clue; its data source is Kitsu).
- The award JSON datasets were compiled offline by Harbor maintainers; freshness unknown (no date field observed).
- Cinemeta `episodes.metahub.space` stills availability is best-effort (fallback only).
- The XML anidb map (`anime-lists`) is community-maintained and may lag current anime.
- Anime4K shader presets execute inside libmpv; actual shader files are native-side (not in this frontend tree).

---

## 11. Parity-critical behaviors (5 most important)

1. **Anime id must resolve to Kitsu before anything renders.** `animeDetails()` returns null if `parseKitsuId` fails and ARM can't map mal:/anilist:/anidb:. The whole anime detail page (episodes, cast, franchise, awards) is Kitsu-driven; TMDB only overlays logos/backdrops when the year-guard (±1) passes.
2. **Episode numbering/playability depends on the anime-kitsu addon videos + AniZip mapping.** Addon `videos[]` are authoritative for playable episode ids and carry the IMDb season/episode numbers; AniZip backfills absolute numbers, filler, tvdb ids, titles, and ratings. Without both, episodes are unplayable or metadata-poor.
3. **Ratings stack per card/detail:** Cinemeta/IMDb (meta.imdbRating) → OMDB (IMDb/RT/Metacritic + Certified Fresh ≥75% & ≥50k votes + awards) → MDBList (Letterboxd/Trakt/RT-audience/Simkl) → harbor-imdb (episodes, anime) → TVDB thumbs. Each layer is independently keyed/optional — a missing key silently drops that badge tier.
4. **Award badges are franchise-key string matching.** Anime award matching (Crunchyroll/TAAF/JMAF/r-anime/Kobe) = normalize title → strip season/part/sequel suffixes → exact key lookup, with a Jikan-resolved synonym cache; Wikidata awards key off IMDb id presence. Mismatched transliterations yield no badge; the synonym map only builds as titles get resolved.
5. **Auth/sync is multi-account and profile-scoped:** AniList/MAL/Trakt/Simkl sessions persist per profile; progress sync is guarded by per-profile "sent" maps and only pushes forward (never regresses); watching-state auto-transitions (PLANNING→CURRENT, auto-COMPLETED at episode count) fire on playback, not on user action.
