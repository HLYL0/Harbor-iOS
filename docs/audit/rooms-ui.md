# Harbor v0.9.21 — UI Rooms / Navigation / Screens — Forensic Report

Audited source: `C:/Users/Admin/AppData/Local/Temp/harbor-ref` (Harbor, a Stremio client — Tauri 2 + React 19 + TanStack Router + libmpv).
Method: static inspection of the router config, the View-stack screen router, every room view, chrome component, and the keyboard/TV navigation layer. **FACT** = verified in source with file:line. **INFERENCE** = reasoned from source structure, not directly observed at runtime.

---

## 1. Architecture summary (FACT)

Harbor has a **two-layer navigation system**:

1. **TanStack Router** (`src/router/router.tsx`, `src/router/paths.ts`, `src/router/sync.tsx`) — a thin shell whose only job is URL/path bookkeeping for the 15 root tabs + `/detail/:type/:id`. Every route component renders `() => null` (router.tsx:31-36, 55-59).
2. **The View stack** (`src/lib/view.tsx`) — the *real* screen router. It maintains a `Frame[]` stack (home → meta → picker → player …), supports back/forward, scroll-memory per room, and keep-alive/eviction of inactive rooms. `App.tsx`'s `Shell` (src/App.tsx:489-1291) maps `topKind` (top-of-stack frame kind) to the mounted screen components and decides which chrome (sidebar/rail/dock/etc.) is visible.

`ViewRouterSync` (src/router/sync.tsx) bridges both directions: View changes push paths; browser back/forward pops to views. Nested frames (meta/person/picker/player/…) are View-only and have no URL (sync.tsx:8 comment).

Screen components live in **`src/views/`** (not `src/screens` or `src/pages`): `src/views/home.tsx`, `src/views/discover.tsx`, `src/views/movies.tsx`, `src/views/shows.tsx`, `src/views/anime.tsx`, `src/views/live.tsx`, `src/views/calendar.tsx`, `src/views/library.tsx`, `src/views/addons.tsx`, `src/views/settings.tsx`, etc., with per-room subdirectories (`src/views/home/`, `src/views/discover/`, `src/views/detail/`, `src/views/live/`, `src/views/library/`, `src/views/addons/`, `src/views/settings/`, `src/views/anime/`, `src/views/calendar/`, `src/views/award/`, `src/views/player/` …).

---

## 2. Complete route list (FACT)

### 2a. TanStack Router tree — `src/router/router.tsx:39-60`

| Path | Component |
|---|---|
| `/` | null (slot — `tabRoute`) |
| `/discover` | null |
| `/catalogs` | null |
| `/movies` | null |
| `/shows` | null |
| `/kids` | null |
| `/anime` | null |
| `/live` | null |
| `/vod` | null |
| `/calendar` | null |
| `/library` | null |
| `/downloads` | null |
| `/addons` | null |
| `/settings` | null |
| `/wrapped` | null |
| `/detail/$type/$id` | null |

Memory history, initial entry `/` (router.tsx:64). `VIEW_PATH` map in src/router/paths.ts:4-20; `metaPath()` builds `/detail/{type}/{id}` (paths.ts:35-37).

### 2b. View enum (root tabs) — `src/lib/view.tsx:23-38`

`home | settings | anime | discover | catalogs | addons | calendar | movies | shows | kids | library | live | vod | downloads | wrapped`
(15 tabs; `/wrapped` has no nav item in the sidebar — reachable from Library "Stats" button and settings.)

### 2c. Frame kinds (full screen stack) — `src/lib/view.tsx:108-152`

Root tabs: home, settings, anime, discover, catalogs, addons, addon-detail(id), calendar, wrapped, queue, movies, shows, kids, library, live, vod, downloads, service(StreamingService).
Stack-only frames: **meta** (Detail), **episode-detail**, **person**, **collection**, **collections**, **filter**, **grid**, **award**, **anime-award**, **picker**, **player**, **match-detail**.

`ROOT_VIEW_BY_KIND` (view.tsx:154-185) maps every frame kind to the tab that stays highlighted under it (e.g. queue→discover, addon-detail→addons; meta/person/picker/player/etc.→null, i.e. last root tab stays active).

### 2d. Screen → component wiring — `src/App.tsx:993-1290` (Shell)

All rooms are kept alive (layered `contents`/`hidden` divs) via `useIdleEvict`/`useKeepAlive` (App.tsx:956-991); each screen is `React.lazy` (App.tsx:132-171) with a two-stage idle preloader (App.tsx:173-230).

| topKind | Component (file) |
|---|---|
| home | `Home` — src/views/home.tsx |
| settings | `Settings` — src/views/settings.tsx |
| anime | `AnimeView` — src/views/anime.tsx |
| discover | `Discover` — src/views/discover.tsx |
| catalogs | `Catalogs` — src/views/catalogs.tsx |
| addons / addon-detail | `AddonsView` — src/views/addons.tsx |
| calendar | `CalendarView` — src/views/calendar.tsx |
| wrapped | `WrappedView` — src/views/wrapped.tsx |
| movies | `Movies` — src/views/movies.tsx |
| kids | `Kids` — src/views/kids.tsx |
| shows | `Shows` — src/views/shows.tsx |
| library | `LibraryView` — src/views/library.tsx |
| live | `LiveView` — src/views/live.tsx |
| vod | `PlaylistVodView` — src/views/playlist-vod.tsx |
| downloads | `DownloadsView` — src/views/downloads.tsx |
| queue | `QueueView` — src/views/queue.tsx |
| service | `ServiceView` — src/views/service.tsx |
| meta | `DetailView` or `KidsDetailView` (kid profile) — src/views/detail.tsx / src/views/kids-detail.tsx |
| person | `PersonView` — src/views/person.tsx |
| collection | `CollectionView` — src/views/collection.tsx |
| collections | `CollectionsView` — src/views/collections.tsx |
| episode-detail | `EpisodeDetailView` — src/views/episode-detail.tsx |
| match-detail | `MatchDetailView` — src/views/live/match-detail-view.tsx |
| filter | `FilterView` — src/views/filter.tsx |
| grid | `GridView` — src/views/grid.tsx |
| award | `AwardView` — src/views/award.tsx |
| anime-award | `AnimeAwardView` — src/views/anime-award.tsx |
| picker | `PlayPicker` — src/views/play-picker.tsx |
| player | `PlayerView` — src/views/player.tsx (renders `PlayerRouteFallback` as Suspense fallback — src/views/player/player-route-fallback.tsx) |

Additional app-level overlay apps (not frames): `multiview.tsx` (mounted by LiveView), `pip.tsx`, `hdr-overlay-app.tsx`, `modal-overlay-app.tsx`, `remote-app.tsx` (remote/session TV companion).

---

## 3. Main rooms — every rail/section (FACT, with rendering files)

### 3.1 Home — `src/views/home.tsx` (1127 lines)

Top-to-bottom order in the render (home.tsx:906-1092), unless user customization reorders (see §3.1c):

1. **TMDB nudge** — `TmdbNudge` (src/components/nudge.tsx), suppressed if a TMDB-provider addon is installed or classic mode (home.tsx:913-917).
2. **Featured hero** — `HeroCarousel` (src/components/hero-carousel.tsx), 4 slides max, ranked badges ("TV"/"Movies" + position), slides picked from heroSource row or hero pool (home.tsx:654-675); `heroFull` setting renders full-bleed (`-mt-24 harbor-hero-full`, home.tsx:938). Hero pool per source:
   - TMDB key: `buildTmdbRows` — first items of trending movies/TV, now-playing, on-the-air (src/views/home/home-rows.ts:89-96).
   - No key: `buildCinemetaRows` — first of topMovies, topSeries, Drama, Comedy, Action, Sci-Fi (home-rows.ts:165-167).
   - Customizable per-row "hero source" (`settings.homeRows.heroSource`, home.tsx:631-652).
3. **Continue Watching** — `CWSection` (src/views/home/cw-section.tsx) → `ContinueCard` (src/components/continue-card.tsx); merges Stremio library + Simkl playback + local playback history, dismissible, deduped by id and normalized name (home.tsx:483-538); advance-to-next-episode via `useCwAdvance` (src/views/home/hooks/use-cw-advance.ts). **Shown in classic mode too.**
4. **Streaming services rail** — `StreamingRail` (src/components/streaming-rail.tsx), from enabled `settings.streaming` services (home.tsx:896-904, 991-995). Hidden in classic mode.
5. **Top 10** — ranked `Row` of `TopRankCard`s (src/components/top-rank-card.tsx), built from the first 10 items of the first data row ("Top 10 on Stremio" / "Top 10 Trending This Week") (home.tsx:694-718, 996-1021). Hidden in classic mode.
6. **Collections** — `CollectionsRow` (src/components/collections-row.tsx) when TMDB key present (home.tsx:1032-1045). Hidden in classic mode.
7. **Customizable rows** — `CustomizableRows` (src/views/home/customizable-rows.tsx) rendering `Row`/`ArrowedScrollRow`/custom-source rows. Row sources in display order (home.tsx:777-802):
   - custom sources (folders) — `source-*` rows (home.tsx:725-740)
   - custom list rows — `list-*` (home.tsx:743-767)
   - pinned rows (`usePinnedRows` — src/views/home/hooks/use-pinned-rows.ts, "Pin to Home" from tracker rails)
   - Arabic localized rows (`buildArabicHomeRows` — src/lib/arabic/home-rows.ts, only when UI language is `ar` + TMDB key)
   - personal rows: "Favorites" (`harbor-favorites`) and "My Watchlist" (`harbor-watchlist`) (home.tsx:600-629)
   - Trakt rows (`buildTraktHomeRows` — src/lib/trakt/home-rails.ts)
   - Simkl rows (`buildSimklHomeRows` — src/lib/simkl/home-rails.ts, gated by `simklHomeRailsEnabled`/`simklUpNextRailEnabled`/`simklTrendingRailEnabled`/`simklGranularFilters`)
   - Letterboxd rows (`buildLetterboxdHomeRows` — src/lib/stremboxd/home-rails.ts)
   - base rows: TMDB build (`buildTmdbSpecs`, home-rows.ts:16-71): Trending This Week (movies), In Theaters Now, Popular Movies, Trending Series, On The Air, Popular Series, Top Rated Series, Top Rated Movies; fallback Cinemeta build (`buildCinemetaRows`, home-rows.ts:99-169): Top 10 on Stremio, Popular Movies, Top 10 Drama, Trending Series, Top 10 Comedy, Action Hits, Sci-Fi & Fantasy, Thrillers, Animated Movies, Horror, Romance, Adventure, Documentaries, Mystery, Fantasy, Drama Series, Comedy Series, Crime Series.
   - anime rows (Jikan, home-rows.ts:171-251): Trending Anime, New Anime Releases, Popular Anime, Upcoming Anime (hidden when `hideContent.anime` or classic mode; hidden when `animeOnlyInAnimeRoom` for CW only)
   - addon catalog rows: `mergeRows` (home-rows.ts:276-327); dedup toggle `homeShowAllAddonRows`; in classic mode addon rows are NOT filtered/deduped (home.tsx:197-210); anime addon rows and streaming-service-named rows are excluded from the non-classic merge (home.tsx:207-209).
8. Row customization UX — `CustomizeBar` (src/views/home/customize-bar.tsx) pinned over hero; edit mode exposes `PinnedRowControls` per pinned section (hero/top10/collections) and `RowControls` (src/views/home/row-controls.tsx) for move/hide/rename/numerals/hero-source per row; add source modal `AddSourceModal` (src/components/add-source-modal.tsx); folder cover editing `EditFolderImagesModal` (src/components/edit-folder-images-modal.tsx). Customization state in `src/lib/home-customization.ts` (`settings.homeRows`).
9. `BackToTop` button (src/components/back-to-top.tsx). Skeleton: `RowSkeleton` (src/views/home/row-skeleton.tsx). Scroll memory: `useScrollMemory("home", …)`.

### 3.1b Classic Stremio Home — `settings.homeMode === "classic"` (FACT)

Home.tsx branches on `settings.homeMode` (home.tsx:175, 698-700, 933, 971, 991, 996): classic removes the **hero, streaming rail, Top 10, Collections** sections; addon catalog rows are rendered **verbatim in addon order** (no dedup, no anime/service filtering, home.tsx:197-210); CW stays. Setting type: `homeMode: "harbor" | "classic"` (src/lib/settings/types.ts:335), default `"harbor"` (src/lib/settings/defaults.ts:302), toggled by `HomeModePicker` in Settings → Library & metadata (src/views/settings/library-panel.tsx:131, 1328+).

### 3.2 Discover — `src/views/discover.tsx` (580 lines)

Render order (discover.tsx:407-572):

1. **Featured & Recommended** — `FeaturedBanner` (src/components/featured-banner/), fed by `buildFeatured`/`buildFeaturedFast`/`rescoreFeatured` (src/lib/feed/featured) — personalized, taste/rescore/subscribe-driven (discover.tsx:135-172). Sub-pieces: big-card-stack.tsx, side-panel.tsx, stepper.tsx, thumbs-dock.tsx, lightbox.tsx.
2. **Browse your catalogs** — `CatalogBrowser` (src/views/discover/catalog-browser.tsx) — genre/collection chips browser.
3. **Can't decide?** — `SurpriseMe` (src/views/discover/surprise-me.tsx).
4. **Letterboxd rows** (if connected) — plain `Row`s of `PickCard` with `LetterboxdRowMenu` (src/components/letterboxd/letterboxd-row-menu.tsx) (discover.tsx:469-501).
5. **~14 daily personalized rails** — `selectDailyRows` (src/lib/feed/daily-rows.ts) → `Rail` (src/views/discover/discover-rail.tsx). Rails are **day-seeded**: pinned anchors in order Trending This Week → Top Rated → Award Winning, shuffled middle rails, rotating closing anchor (documentaries / hidden gems / cult) (daily-rows.ts:92-129). Anchor titles: src/lib/feed/daily-rows-anchors.ts (Trending This Week, Award Winning, Top Rated, Highly Rated Quietly Loved, Cult Classics, Animated For Grown-Ups, Documentaries Worth Your Night, Recently Released). Middle-rail titles generated per catalog in src/lib/feed/daily-rows-catalog.ts (Top Rated {Genre}, New in {Genre}, Hidden Gems from the {Decade}, Best of the {Decade}, {Language} Films, A Short Tonight, New {Service} Series, "On {service}, picked for you", etc.) and people rows (src/lib/feed/daily-rows-people.ts: More from {Director}, Starring {Actor}, More stories like these). Without TMDB key: `fallbackShelves` (src/lib/feed/themes.ts). Recency ring avoids repeating rails across 10 days (localStorage `harbor.discover.rows.v1`).
   **Interspersed tiles at fixed rail indices** (discover.tsx:557-570): after rail 0 → `GenreTiles` (src/components/genre-tiles.tsx); after rail 1 → `DiscoveryQueueCta` (src/components/discovery-queue-cta.tsx); after rail 2 → `LanguageTiles` (src/components/language-tiles.tsx) + `CollectionsRow` (TMDB key); after rail 3 → **Critics Pick** (`CriticsPick` — src/components/critics-pick/, day-rotated from `fetchCriticsPickList`); after rail 4 → `AwardTiles` (src/components/award-tiles.tsx).
6. Customization: `CatalogCustomizeBar` (src/components/catalog/customize-bar.tsx) + `SectionEditBar` (src/views/discover/section-edit-bar.tsx) + `RowControls`; persistence via `usePageRows("discover")` (src/lib/page-rows.ts) — hide/reorder/rename sections and rails.
7. Dedup across rails: `useDedupedRows` (src/views/discover/use-deduped-rows.ts) with priority to Top Rated and Awards rails (discover.tsx:56, 361).

### 3.3 Movies — `src/views/movies.tsx` (289 lines)

1. **CinemaHero** — `CinemaHero` (src/components/cinema-hero.tsx), slides from `buildMovieHero` (TMDB: top-rated ×2 + prestige ≥8.0/4000 votes ×2 + modern ≥7.8/2500; daily rotation `rotateDaily`, src/views/movies/movie-specs.ts:17-76) or Cinemeta fallback.
2. **Letterboxd rows** (if connected) — `Row` + menu (movies.tsx:213-251).
3. **Top 10 Movies Today** — ranked `TopRankCard` row from the `trending` catalog row head (movies.tsx:151-155, 252-274).
4. **Catalog rows** — `CatalogRows` (src/components/catalog/catalog-rows.tsx), specs from `movieSpecs` (src/views/movies/movie-specs.ts:78-234): Trending This Week, In Theaters Now, 3 daily mood rows (`pickMoodSpecs` — src/lib/feed/moods.ts), Critics' Picks, All-Time Greats, Hidden Gems, Quick Watches Under 90, Coming to Theaters, Defining the 2010s, Essential 90s, 80s Classics, 70s Auteurs, Japanese Cinema, Korean Cinema, French Cinema, Documentary Spotlight. Cinemeta fallback specs: Top Movies + Top {13 genres} (movies.tsx:41-64).
5. `TmdbNudge`, `CatalogCustomizeBar`, `usePageRows("movies")` customization, `BackToTop`, scroll memory. Data plumbing: `useCatalogPage` (src/lib/catalog-page.ts).

### 3.4 Shows — `src/views/shows.tsx` (291 lines)

Same skeleton as Movies with:
1. **PageMast** + **PeekHero** (src/components/peek-hero.tsx) — hero from `buildShowHero` (src/views/shows/hero-curation.ts): 240-title cached pool (24h TTL), day-part copy ("Morning Lineup" / "Afternoon Picks" / "Evening" / "Night" kickers).
2. Top 10 row from `trending` spec (shows.tsx, same pattern as Movies).
3. **Catalog rows** from `showSpecs` (src/views/shows/show-specs.ts:12-227): Trending This Week, On Tonight, Premiered This Month, From HBO, Netflix Originals, Apple TV+, AMC, FX, Disney+ Originals, Prime Video, Limited Series & Miniseries, Prestige Drama, Comedy Series, Crime & Mystery, Sci-Fi & Fantasy, Documentary Series, All-Time Great Series, Iconic Long-Runners, K-Drama, British Television. Cinemeta fallback: Top Series + genres (shows.tsx:50-64).
4. Letterboxd rows + customization identical to Movies.

### 3.5 Anime — `src/views/anime.tsx` (735 lines)

Render order (anime.tsx ~600-735):

1. **AnimeHero** — `AnimeHero` (src/components/anime-hero.tsx) or hosted hero (`fetchHostedHero` — src/lib/anime-hosted-hero.ts, `buildHostedHero`/`resolveHeroSlides`/`cacheHero` — src/views/anime/hero-build.ts), with genre "Tune" button opening `AnimeGenrePicker` (src/components/anime-genre-picker.tsx) and MAL/AniList filter chips (anilist-top-row etc.).
2. **Continue Watching** — anime-scoped CW row (`ContinueCard`), respects `animeOnlyInAnimeRoom` (anime.tsx ~613-626).
3. **MalRows** — "Your MAL: {rail}" (src/views/anime/mal-rows.tsx) — hidden per `malRowsHidden` (`yourMalLists`).
4. **AnilistRows** — "Your AniList: {rail}" (src/views/anime/anilist-rows.tsx) — hidden per `animeAnilistRowsHidden` (`yourLists`).
5. **AnilistRowControls + MalRowControls** (row management toggles, src/views/anime/anilist-row-controls.tsx, mal-row-controls.tsx).
6. **AnilistTrendingRow** + **AnilistTopRow** (Top 100) — src/views/anime/anilist-top-row.tsx (hidden per `trending` / `top100`).
7. **Award Winning Anime** row (`awardWinnerMetas`, `awardLookupByMetaId`).
8. **Jikan catalog rows** (`SPECS` — src/views/anime/anime-rows.tsx:26-110): Airing Now, **Top Airing on MAL (ranked Top 10)**, Upcoming Season, **Top Series on MAL (ranked)**, Top Movies on MAL, Most Popular on MAL, Top Rated on MAL, Hidden Gems on MAL, 2020s Hits, 2010s Classics, 2000s Era, Foundation Years (90s), Action & Adventure, Romance, Slice of Life, Mecha, Fantasy, Sci-Fi, Psychological, Horror & Supernatural. Ranked rows render `AnimeRankCard` Top-10 style.
9. **Addon rows** (deduped) — merged from `loadAddonRows` (anime.tsx, `dedupedAddonRows`).
10. Row picker: `AnimeGenrePicker` (favorite-genre tuning, `animeFavoriteGenres`). Franchise suffix stripping (`stripFranchiseSuffix` — src/lib/providers/jikan.ts). Filters: `animeFiltered` / `filterOpts` (adult/ratings gating). Hidden-content guard: `settings.hideContent.anime` redirects to home (App.tsx:866).

### 3.6 Live TV — `src/views/live.tsx` (405 lines)

Not a rail page — a **4-mode app** (`ViewMode` persisted in localStorage `harbor.iptv.viewMode`, live.tsx:29-64):

- **home**: `LiveHome` (src/views/live/live-home.tsx) — hero/what's-on now, favorites-first channel rails.
- **grid**: `CategorySidebar` (src/views/live/category-sidebar.tsx, group list w/ counts + logos + favorites) + optional `TopNetworksRows` (src/views/live/top-networks-rows.tsx, region rows) + `ChannelGrid` (src/views/live/channel-grid.tsx, channel cards with EPG "now playing", `onInfo` → Detail with `liveContext: true`).
- **guide**: `GuideView` (src/views/live/guide/guide-view.tsx) — timeline EPG grid, play + catch-up.
- **multiview**: `MultiviewView` (src/views/multiview.tsx) — Windows-desktop-only (live.tsx:53); immersive mode hides chrome (`harbor:immersive`, live.tsx:144-152; App.tsx:931-946 sets `data-chrome-hidden`).
- Header chrome: `SourcePicker` (src/views/live/source-picker.tsx — M3U/EPG/Xtream source add/edit/remove/reorder/export/refresh), channel search box, `ViewModeToggle` (src/views/live/view-mode-toggle.tsx).
- States: `PlaylistEmpty` (src/views/live/playlist-empty.tsx), `GridSkeleton`/`GuideSkeleton`, `EmptyResult`, `ErrorBlock`, EPG-fail banner.
- Data: `useIptvPlaylist`, `useEpg` + `useXtreamEpgFallback`, `useChannelPipeline` (region/language/favorites/query filtering), `useFavorites` (src/lib/iptv/favorites.ts — favorites appear as a category group).
- Match detail: `MatchDetailView` (src/views/live/match-detail-view.tsx) as its own frame (sports — src/lib/sports/espn.ts).

### 3.7 Calendar — `src/views/calendar.tsx` (326 lines)

1. Header: "Releases / Calendar" display heading, prev/Today/next month controls, `SourceSwitcher` (sources: `all` (TMDB), `library` (Stremio), Trakt, Simkl, `simkl-anticipated`, `custom`), "Start week on Monday" toggle, `CustomCalendarBar` (src/views/calendar/custom-bar.tsx) for custom sources.
2. Filter pills `FILTERS` (src/views/calendar/utils.ts): all / movies / shows / anime-style type filters + counts, "Watchlist only" (library-membership filter).
3. Body: `MonthGrid` (src/views/calendar/month-grid.tsx) — day cells with `CalendarChip`s (src/views/calendar/calendar-chip.tsx); click day → `DayModal` (src/views/calendar/day-modal.tsx); click item → Detail with `episodeHint`.
4. States: `CalendarSkeleton`, `EmptyState`/`ErrorState`/`NoKeyState`/`NotSignedInState` (src/views/calendar/empty-states.tsx); auth via `AuthModal` (src/components/auth-modal/).
5. Data: `useCalendarData` (src/views/calendar/use-calendar-data.ts), `applyCalendarFilter`/`groupByDate` (src/lib/calendar.ts).

### 3.8 My Library — `src/views/library.tsx` (232 lines) + tabs

Tab bar (library.tsx:180-227; persisted `harbor.library.tab`):
- **Watchlist** — `WatchlistTab` (src/views/library/watchlist-tab.tsx, `WatchlistCard` src/views/library/watchlist-card.tsx)
- **History** — `HistoryTab` (src/views/library/history-tab.tsx, `HistoryEpisodeCard`)
- **Local** — `LocalTab` (src/views/library/local-tab.tsx — local file folders)
- **My Lists** — `MyListsTab` (src/views/library/my-lists-tab.tsx; list detail `ListDetail` src/views/library/list-detail.tsx)
- **Trakt** (if connected) — `TraktTab` (src/views/library/trakt-tab.tsx)
- **AniList** (if connected) — `AnilistTab` (src/views/library/anilist-tab.tsx, `AnilistEntryCard`)
- **MAL** (if connected) — `MalTab` (src/views/library/mal-tab.tsx, `MalEntryCard`)
- **Simkl** (if connected) — `SimklTab` (src/views/library/simkl-tab.tsx)
- **Letterboxd** (if active) — `LetterboxdTab` (src/views/library/letterboxd-tab.tsx)

Header: "Your collection." + optional **Stats** button → Wrapped (library.tsx:170-178). Disconnected tabs auto-fallback to watchlist (library.tsx:66-84).

### 3.9 Addons — `src/views/addons.tsx` (684 lines)

3 tabs (addons.tsx:304-513): **Discover** (`DiscoverPane` — src/views/addons/discover-pane.tsx: `HeroCard`, curated `Rail`s incl. "essential" rail + "Editor's Picks", `FeatureCard`, `CommunityAddonsRail` src/components/community-addons-rail.tsx, `DetailRail`, `AddonMosaicBackdrop` src/components/addons-mosaic-backdrop.tsx) · **Browse** (`BrowsePane` — src/views/addons/browse-pane.tsx: `CommunityBrowseList` src/views/addons/community-browse-list.tsx, `CategoryGrid` src/views/addons/category-grid.tsx, `SearchBar` src/views/addons/search-bar.tsx, add-by-URL bar src/views/addons/add-by-url-bar.tsx, `TagRow`, adult-filter toggle) · **Installed** (`InstalledPane` — src/views/addons/installed-pane.tsx: `InstalledRow` list with enable/configure, `InstallPill`, reorder drag list `useDragList` via **Organize** page src/views/addons/organize/page.tsx with `SectionCard`/`BackupsCard`).
- Addon detail: `AddonDetailView` within addons (src/views/addons/addon-detail.tsx, `AddonDescription`, `AddonDocumentation`, `InstallModal` src/views/addons/install-modal.tsx, `TorrentioHeroArt`, `CinemetaPosters`, `Toaster`).
- Deep-link install: `stremio://install` → jumps to Addons (App.tsx:834-836).

### 3.10 Settings — `src/views/settings.tsx` (384 lines)

Left nav (`SECTION_META`, settings.tsx:83-95 + `SettingsSection` type src/lib/view.tsx:201-212) → right lazy panels (settings.tsx:302-375):

| Section | Panel file |
|---|---|
| Account (basics) | src/views/settings/basics-panel.tsx (+ account.tsx) |
| Library & metadata | src/views/settings/library-panel.tsx |
| Trakt | src/views/settings/trakt-panel.tsx |
| AniList | src/views/settings/anilist-panel.tsx |
| MyAnimeList | src/views/settings/mal-panel.tsx |
| Simkl | src/views/settings/simkl-panel.tsx |
| Letterboxd | src/views/settings/letterboxd-panel.tsx |
| Harbor Relay | src/views/settings/relay-panel/ |
| Streaming sources | src/views/settings/streaming-sources-panel.tsx |
| Stream filters | src/views/settings/stream-filters-panel.tsx |
| P2P & servers | src/views/settings/p2p-panel.tsx |
| Languages | src/views/settings/language-panel/ |
| Player & quality | src/views/settings/quality-panel.tsx |
| Video tuning | src/views/settings/mpv-panel/ |
| Anime tweaks | src/views/settings/anime-panel/ |
| Player layout | src/views/settings/player-layout-panel/ |
| Hotkeys | src/views/settings/hotkeys-panel.tsx |
| Theme & appearance | src/views/settings/theme-panel.tsx |
| Webhooks | src/views/settings/webhooks-panel.tsx |
| Report a bug | src/views/settings/bug-report/ |
| Advanced | src/views/settings/advanced-panel.tsx |

Settings nav is a slide-over/panel layout; settings hides all chrome except topbar (App.tsx:995-1016 conditions) and is the only room that is idle-evicted when pinned as overlay (`useOverlayPinned`, App.tsx:957). Section deep-links via `openSettings(section)` (view.tsx:217-218). Settings search exists (`settings-search.test.ts`). Nav customization lives in Settings (nav order/hide/rename — `settings.navCustomization`, src/chrome/nav-items.tsx:45-49, 140-201).

### 3.11 Secondary rooms (FACT, brief)

- **Kids** — `src/views/kids.tsx`: `KidsHero` (src/views/kids/kids-hero.tsx) + catalog rows from `kidsSpecs` (src/views/kids/kids-specs.ts: Trending for Kids, Animated Movies, G and PG Picks, Kids TV, Family TV Nights, Adventures, Sing-Along and Musicals); franchises rail (src/views/kids/kids-franchises.ts, kids-franchise-rail.tsx); kid-profile Detail = `KidsDetailView` (src/views/kids-detail.tsx). Kid profiles force `sidebar` layout and lock navigation to kids/meta/picker/grid/collection (App.tsx:527, 869-890).
- **Catalogs** — `src/views/catalogs.tsx`: user catalog management — `CatalogManageList` (src/views/catalogs/catalog-manage-list.tsx) + grouped `CatalogShelf`s (src/views/catalogs/catalog-shelf.tsx), per-catalog filter select (`addon-filter-select.tsx`), `useCatalogList` (src/views/catalogs/use-catalog-list.ts).
- **Playlists (VOD)** — `src/views/playlist-vod.tsx`: Xtream VOD/Catch-up — movies & series with episode lists (gated by `settings.showPlaylistsTab` in the rail, siderail.tsx:40).
- **Downloads** — `src/views/downloads.tsx`: grouped download list (show groups, item rows, progress), `DownloadsNavIcon` badge in chrome (src/chrome/downloads-nav-icon.tsx).
- **Wrapped** — `src/views/wrapped.tsx`: stats cards (`HeroCard`, `SplitCard`, `TopTitlesCard`, `GenresCard`, `HeatmapCard` — src/views/wrapped/cards.tsx); source gating (Trakt/Simkl/Stremio/local).
- **Queue** — `src/views/queue.tsx`: discovery queue (up/down-voted feed pool). Root view = discover.
- **Service** — `src/views/service.tsx`: per-streaming-service hub ("Top 10 Movies on X", "Movies on X", series equivalents) — `ServiceLogo` (src/components/service-logo.tsx).
- **Collection / Collections** — `src/views/collection.tsx` (single TMDB collection detail with parts), `src/views/collections.tsx` (all-collections index, `CollectionCard` src/components/collection-card.tsx).

---

## 4. Detail page sections — `src/views/detail.tsx` (1856 lines) (FACT)

### Hero band (detail.tsx:1276-1533)
1. **Backdrop** — rotating carousel of `backdropPool` or single `HeroBackdrop` (src/views/detail/hero-backdrop.tsx); full-bleed 78vh (`harbor-bleed-stremio`).
2. **Autoplaying hero trailer** — `DetailHeroTrailer` (src/views/detail/detail-hero-trailer.tsx) when `settings.detailTrailerAutoplay`.
3. **Tagline**, **TitlePlate** (logo or title — src/views/detail/title-plate.tsx), **hero pills**: MPAA rating, local-library pill, **HeroRatings** (src/views/detail/hero-ratings.tsx — IMDb/TMDB/MDLbList scores), runtime (opens runtime filter), genres (open genre filters), addon origin chip.
4. **Hero action bar**: Watch button (`PlayModeHint`), Trailer preview button (`PreviewIcon` → `TrailerOverlay` src/views/detail/trailer-overlay.tsx + `TrailerControls`), episode download (`EpisodeDownloadButton` src/views/detail/episode-download-button.tsx), `HeroActionOverflow` (src/views/detail/hero-action-overflow.tsx — subtitles/audio/download/identify), Trakt/MAL/AniList/Simkl buttons, `AddToAnilistButton`, `AddToSimklButton`, `PromoteMetaToRoot` ("Open in TV Shows/Movies/Anime" for live context).
5. **Awards corner** — `HeroAwardsCorner` (src/views/detail/hero-awards.tsx) or `CrunchyrollAwardsCorner` (src/views/detail/crunchyroll-corner.tsx) inline.
6. Trailer modal — `TrailerOverlay`; native trailer player `NativeTrailerPlayer` (src/views/detail/native-trailer-player.tsx).

### Body (detail.tsx:1535-1620)
7. **Synopsis** (src/views/detail/synopsis.tsx) + **ParentalGuideHeroCard** (src/views/detail/parental-guide-section.tsx).
8. **StreamingLinks** (anime streamers — src/views/detail/streaming-links.tsx) or **WatchOn** (TMDB providers — src/views/detail/watch-on.tsx).
9. **Episodes**: anime → `AnimeEpisodes` (src/views/detail/anime-episodes/ — franchise nav, season picker, episode strip `anime-episode-strip.tsx`, AI search bar `anime-ai-bar.tsx`, random episode, order utils); TMDB series → `SeriesEpisodes` (src/views/detail/series-episodes/ — season selector, episode grid `episode-grid.tsx`, `EpisodePager`, `EpisodeSearch`, layout toggle, rating badges, stremio watched marks); addon-native fallback → `CinemetaEpisodes` (src/views/detail/cinemeta-episodes.tsx).

### Customizable rail sections (detail.tsx:1619-1800, `railSections` = `DetailSection[]`, reorderable/hideable, persisted per user)
- **Credits** — `Credit` rows (src/views/detail/credit.tsx): Director, Writers, Producers, Cinematography, Music, Editors.
- **Cast · {n}** — `CastCard` (src/views/detail/cast-card.tsx).
- **Collection** — `CollectionRow` (src/views/detail/collection-row.tsx).
- **More Like This** (TMDB recommendations) and **You Might Also Like** (similar) — `PickCard` rows.
- **Media** — `MediaGallery` (src/views/detail/media-gallery/ + `MediaLightbox` src/views/detail/media-lightbox.tsx).
- **Awards** — anime: `AnimeAwardsBlock` (src/components/anime-awards-block.tsx); non-anime: `AwardsBlock` (src/components/awards-block.tsx).
- **Information** — `InfoBlock` (src/views/detail/info-block.tsx).
- **Comments** — `TraktComments` (src/views/detail/trakt-comments.tsx) or `AnilistComments` (src/views/detail/anilist-comments.tsx) (settings-gated).
- **Letterboxd** — `LetterboxdPanel` (src/views/detail/letterboxd-panel.tsx) + `LetterboxdReviews` (src/views/detail/letterboxd-reviews.tsx).
- Rendered through `ContentRails` (src/views/detail/content-rails.tsx) with jump navigation (section nav pills). Other bits: `Badges` (src/views/detail/badges.tsx), `DubSubPill`, `MetaAwardsCorner`, `UpcomingCta` (src/views/detail/upcoming-cta.tsx) for unreleased titles, `Pill` (src/views/detail/pill.tsx).

---

## 5. Person / Award / Search / Filter / Grid / Player screens (FACT)

- **Person** — `src/views/person.tsx` (229): profile header (name, department, birthday, bio, "Open Top 100 {dept}" → Award view), `FilmRow`s (src/views/person/film-row.tsx): Known For, Movies · {n}, TV Shows · {n}, Directing, Writing, Producing, Other Work; `PersonLink`/`PersonHoverCard` components (src/components/person-link.tsx, person-hover-card.tsx) used in credits; open via cast cards and search PeopleRow.
- **Award** — `src/views/award.tsx` (213): `AwardHero` (src/views/award/award-hero.tsx), `AwardList` (src/views/award/award-list.tsx — year-by-year winners), `FilmGrid` (src/views/award/film-grid.tsx), `PeopleRail`s — Celebrated actors / Acclaimed directors / Honored writers (src/views/award/people-rail.tsx). Wikidata-backed `AwardType` (src/lib/providers/wikidata.ts).
- **Anime award** — `src/views/anime-award.tsx` (351): award source picker (Crunchyroll etc. — src/lib/anime-awards.ts), winner rows per year with TMDB resolution.
- **Search** — overlay, not a route: `SearchOverlay` (src/components/search/search-overlay.tsx) + `SearchHotkey` (src/components/search/search-hotkey.tsx) mounted app-wide (App.tsx:342-343). Sections: input with **AI mode** (`AiSearchSection` src/components/search/ai-search-section.tsx, `AiModeButton`, `AiExampleHint`; keys: `settings.aiSearchKey`/`aiGroqKey`, model `aiSearchModel`), `TopMatch`, `LiveTvRow`, `AnimeRow`, `MetaList` (movies/shows), `PeopleRow`, `AddonHits`/`AddonResults` (catalog search), `MagnetCard` (magnet URI input), `UrlCard` (direct video URL), `EmptyState`, `ResultPoster`. Display-state logic in src/lib/search-display-state (tested by `search-display-state.test.ts`, `search-request-guard.test.ts`). Opened from chrome search pills (sidebar/topbar/rail/minui).
- **Filter** — `src/views/filter.tsx` (54): `Header` (src/views/filter/header.tsx) + `Rails` (src/views/filter/rails.tsx) for a `MetaFilter` (year/runtime/genre/studio/country/language/network — view.tsx:99-106); genre spotlights (`selectSpotlights` src/lib/feed/genre-spotlights.ts, spotlight gating). Opened from Detail pills/runtime/genres and catalog chips.
- **Grid** — `src/views/grid.tsx` (153): "View all" target — `VirtualGrid` (src/components/virtual-grid.tsx), paginated fetcher, header with count.
- **Play Picker** — `src/views/play-picker.tsx` (896): source resolution screen (scored streams by tier, `ScoredStream`, `buildMatchScores`, torrentio special-case, `SourceDrawer` src/views/play-picker/source-drawer.tsx, `SourceDiagnostic`, `NoSourcesConfiguredModal`, `LocalStreamCard`, `SubtitleSelectStep`, season-source lock, remember-last-stream, auto-play intent, download intent).
- **Player** — `src/views/player.tsx` (1091) + src/views/player/*: libmpv-backed; overlay layers `PlayerOverlayLayers` (src/views/player/player-overlay-layers.tsx) composed of `ShellLayer`, `PanelsLayer`, `ToolsLayer`, `StageOverlays`, `LiveLayer` (live TV), `CastLayer`/`CastingOverlay` (Chromecast), `LoaderLayer`, `RoomLayer` (together watch), skip pills, text-sync overlays, buffering indicator, HDR bridge (`hdr-stage-bridge.tsx`), source error cards, close requests (`request-player-close.ts`). Player transport chrome can render as **Stremio-style** via `resolveChromeTheme(settings.theme, settings.playerChromeTheme)` (src/views/player.tsx:95, src/components/player/transport.tsx:163).
- **PIP** — `src/views/pip.tsx` (425): picture-in-picture overlay app.

---

## 6. Navigation chrome variants (FACT)

Chrome is selected by **theme layout** (`activeLayout(settings.theme)` — src/lib/theme.ts:1726-1729; `ThemeLayout` union theme.ts:24-34; preset layout in theme presets; kid profiles force `sidebar` — App.tsx:527). Mount conditions in App.tsx:995-1033 (all variants hidden when `settingsTop || playerActive || pickerTop`; live multiview immersive additionally hides via `data-chrome-hidden`):

| Layout | Component | File | Shape |
|---|---|---|---|
| `sidebar` (default) | `Sidebar` | src/chrome/sidebar.tsx (370) | Left sidebar: brand, scrollable nav (grouped sections), search, profile chip, window controls; nav overflow support |
| `dracula` | `DraculaSidebar` | src/chrome/dracula-sidebar.tsx (247) | Sidebar (Dracula theme) + `KidsSidebarDoodles` |
| `nord` | `NordSidebar` | src/chrome/nord-sidebar.tsx | Sidebar (Nord theme) |
| `forest` | `ForestSidebar` | src/chrome/forest-sidebar.tsx | Sidebar (Forest theme) |
| `stremio` | `StremioRail` | src/chrome/stremio-rail.tsx (197) | **Classic Stremio-style left icon rail** (icon-only tabs, avatar at top) |
| `topdock` | `TopDock` | src/chrome/topdock.tsx (1032) | Top horizontal dock with pinned tabs + `OverflowNav` (src/chrome/nav-overflow.tsx), liquid-glass surface, search pill, profile chip |
| `rail` | `SideRail` | src/chrome/siderail.tsx (246) | Right-side(ish) elegant rail: brand, PRIMARY nav (home/discover/movies/shows/kids/anime/live/vod), gold-rule separated SECONDARY (calendar/library/downloads/addons/…), search + `RecordingPill` + `TogetherButton` + collapse toggle + `ProfileBlock` (src/chrome/siderail/profile-block.tsx) + window controls |
| `royal` | `RoyalTopbar` | src/chrome/royal-topbar.tsx (681) | Top bar with filigree + `HoverNavIcon` (src/chrome/hover-nav-icon.tsx) |
| `cinematic` | `CinematicOverlay` | src/chrome/cinematic-overlay.tsx (272) | Floating overlay chrome (top bar + nav, hides on scroll) with `ProfileChipCompact` |
| `minui` | `MinUIDock` | src/chrome/minui-dock.tsx (151) | Bottom magnifying dock (`magnify()` distance scaling, minui-dock.tsx:146) + `DockButton` + `FloatingTop` (src/chrome/minui-dock/floating-top.tsx) — visible even in Settings (App.tsx:1016) |
| `custom` | `CustomLayoutSafetyNet` + window controls + `FloatingBack` | src/chrome/custom-layout-safety-net.tsx | User CSS-injected custom chrome; safety net restores default |

Shared pieces: `Topbar` (src/chrome/topbar.tsx, 684 — shown for sidebar/dracula/nord/forest/stremio layouts and in settings; back button `BackChrome` src/chrome/back-chrome.tsx, `SearchPill`, `TogetherButton`, profile menu, recording pill), `FloatingBack` (src/chrome/floating-back.tsx — for layouts without topbar), `WindowControls` (src/chrome/window-controls.tsx), `WindowResizeEdges` (src/chrome/window-resize-edges.tsx), `OfflineBanner` (src/chrome/offline-banner.tsx), `KidsSidebarDoodles` (src/chrome/kids-sidebar-doodles.tsx), `DownloadsNavIcon` badge, `NavOverflow` (`OverflowNav`), nav customization shared via `NAV_ITEMS`/`applyNavCustomization` (src/chrome/nav-items.tsx:51-138 — 14 items: home, discover, catalogs, movies, shows, kids, anime, live, vod, calendar, library, downloads, addons, settings).

Nav customization (`settings.navCustomization`): reorder, hide, rename; parental gates (`parentalKey`) show `ParentalPinModal` (src/components/parental-pin-modal.tsx); settings item is `pinGated`; anime/liveTv hidden via `hideKey` + `settings.hideContent`; vod gated by `settings.showPlaylistsTab` (siderail.tsx:40).

---

## 7. Classic Stremio mode (FACT)

Two independent "classic" levers:
1. **Home layout**: `settings.homeMode: "harbor" | "classic"` (src/lib/settings/types.ts:335; default "harbor" src/lib/settings/defaults.ts:302; picker in src/views/settings/library-panel.tsx:131/1328). Classic = Stremio-style home: no hero carousel, no StreamingRail, no Top 10, no Collections section; addon catalog rows rendered in their native order without dedup/filtering; CW row retained (src/views/home.tsx:175-210, 698-700, 933-982, 991-1021).
2. **Chrome style**: `stremio` theme layout renders the `StremioRail` (icon rail à la Stremio's left bar) — src/chrome/stremio-rail.tsx; and the **player transport** can be forced to Stremio chrome independently via `settings.playerChromeTheme` (`resolveChromeTheme`, src/lib/theme.ts:1731-1739).
The onboarding flow does not set classic mode; it signs into Stremio (src/components/onboarding/stremio-step.tsx).

---

## 8. Keyboard / TV-style navigation (FACT)

- Core: `useKeyboardNavigation` (src/lib/keyboard-navigation.ts, 1208 lines) — enabled by `settings.tvNavigation`, disabled during playback (App.tsx:584-589). Arrow keys = directional spatial navigation; Enter/Space = activate; **focus ≠ activation** (inputs need explicit activation — AGENTS.md "Navigation and Input"; HTPC search-edit mode, keyboard-navigation.ts:140-160).
- Back handling: `handleTvBack` (App.tsx:541-574) — search close → exit player → exit picker → `goBack()`; `handleTvBackToNav` refocuses `[data-harbor-nav]`/`[data-tv-nav-zone]`/`[data-harbor-sidebar]` (App.tsx:576-582). Mouse button 4/5 = back/forward (App.tsx:682-706). `harbor:local-back` event for room-internal back (e.g. Live TV modes, live.tsx:129-143).
- Focus scopes & selectors: `[data-tv-focus-scope]`, `[data-tv-nav-zone]`, `[data-harbor-sidebar]`, `[data-tv-top-chrome]`, `[data-tv-hero-zone]`, `[data-media-card]`, `[data-tv-initial-focus]`, `[data-tv-modal-close]`, `[data-tv-focused]`, `focusTvPageDefault()` (keyboard-navigation.ts:187-396).
- Focus ring: injected theme-aware styles using `var(--color-accent)` (keyboard-navigation.ts:421-450; asserted by tests/keyboard-focus.test.ts).
- Hotkeys: `src/lib/hotkeys.ts` (`shouldHandleGlobalKeyboardEvent`, `eventToBinding`, user-overridable `settings.hotkeys`); F11 fullscreen; Ctrl/Cmd +/-/0 UI scale (App.tsx:712-785).
- Tests: `tests/keyboard-focus.test.ts` (source-level assertions: TV intent gating, theme-aware ring without hard-coded whites, hotkey guards), `tests/view-lifecycle.test.ts`, `tests/search-display-state.test.ts`, `tests/tanstack-foundation.test.ts`.
- Gamepad/remote: AGENTS.md requires keyboard/remote/gamepad consistency; remote session support exists (`src/lib/remote/`, `src/views/remote-app.tsx`, `armRemoteStickyHop` in view.tsx:19) — **INFERENCE**: gamepad input handling beyond hotkeys was not found in the frontend (likely native/Tauri side).

---

## 9. FACT vs INFERENCE register

**FACT (verified in source):**
- Router table (§2a), View enum and Frame union (view.tsx), screen wiring in App.tsx Shell, all room rail lists and file paths above, chrome variant mount conditions (App.tsx:995-1033), classic mode branches, TV nav structure, keyboard-focus.test.ts contents, settings panel list, addons tabs, live TV modes, detail sections order (railSections construction order), discover rail anchoring/ordering algorithm.

**INFERENCE (not directly verified at runtime):**
1. Exact visual order of interspersed Discover tiles at runtime — source places them after rails 0/1/2/3/4 of the *visible* (customized) list, but if the user hides/reorders rails the indices shift (discover.tsx:557-570 is index-based, not id-based). This is a plausible parity gotcha.
2. Default nav order across chrome variants is `NAV_ITEMS` order (nav-items.tsx:51-138) until a user customizes; SideRail groups it into primary/secondary sets (siderail.tsx:19-48).
3. StremioRail exact interaction behavior (hover expansion of icons) — only icon rail structure verified, not runtime animation.
4. Gamepad navigation implementation location (likely native side, not found in `src/`).
5. Which theme preset maps to which layout by default (theme presets store `layout`; individual preset→layout pairs were not enumerated here).
6. Player overlay z-order/visibility timing is mpv-event driven; exact visual states were not exercised.
7. `homeShowAllAddonRows`, dedup thresholds, and rail-minimum filters (≥4 items) affect final visible rail counts; exact counts at runtime depend on settings/network.

---

## 10. Parity-critical behaviors — top candidates

1. **Home room composition & customization model** — hero (rotating, rank badges, full-bleed option) + CW + streaming rail + Top-10 ranked row + collections + fully reorderable/hideable/renameable rows with per-row hero-source and numerals; classic mode collapses all of this to raw addon rows. Any iOS port must reproduce the customization state model (`settings.homeRows` in src/lib/home-customization.ts) or Home will feel wrong.
2. **Discover's daily-seeded personalization** — 14 rails/day, deterministic day seed, anchors (Trending/Top Rated/Awards) pinned, rotating closing anchor, recency ring over 10 days, taste/rescore pipeline (up/down-votes), fixed-index tile insertions (Genres, Queue CTA, Languages, Collections, Critics Pick, Award tiles). This is the most algorithm-heavy room.
3. **Detail page rail system** — user-customizable rail order/visibility (`DetailCustomization`), the triple episode pipeline (AnimeEpisodes vs SeriesEpisodes vs CinemetaEpisodes fallback), hero autoplay trailer, ratings block, awards corners, Letterboxd/Trakt/AniList comment sections, and live-context "Open in …" promotion.
4. **Two-layer navigation** (TanStack shell for tab URLs + View stack for nested frames) with scroll memory per room, keep-alive/idle-eviction, back/forward, `harbor:local-back` room-internal back, and `ROOT_VIEW_BY_KIND` tab highlighting — plus kids-profile lockdown (sidebar layout, allowed frame whitelist).
5. **Chrome theme matrix** — 11 layouts (sidebar/dracula/nord/forest/stremio/topdock/rail/royal/cinematic/minui/custom) each with distinct mount/visibility rules (settings/player/picker/immersive exceptions), nav customization shared across all, and Stremio-classic double lever (homeMode + stremio layout + playerChromeTheme).
