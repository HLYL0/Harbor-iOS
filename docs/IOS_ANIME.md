# IOS Anime

> Anime subsystem design — first-class, never a genre filter (spec §25). Behavior source: `docs/audit/metadata-anime.md` (verified).

## 1. The dependency spine (parity-critical #1)

**Anime id MUST resolve to Kitsu before anything renders.** The entire anime detail surface (episodes, cast, franchise, awards) is Kitsu-driven; TMDB only overlays logos/backdrops when the year-guard (±1) passes. Port `parseKitsuId` + ARM/AniZip mapping for mal:/anilist:/anidb: ids; `animeDetails()` returns null when unresolvable — **same null behavior**.

## 2. Episode pipeline (parity-critical #2)

- Playable episodes = **anime-kitsu addon `videos[]`** (authoritative; carries IMDb season/episode numbers) + **AniZip** backfill (absolute numbers, filler, tvdb ids, titles, ratings).
- AniZip: 90ms throttle, 4s timeout. Jikan: 400ms throttle. OMDB: daily budget (default 1000), 90% prefetch cutoff.
- Episode file matching + season packs: from `IOS_STREAM_ENGINE.md` §3 (anitomy enhancer, batch detection, `episodeFileRegex`).
- Dub badge: works only for mal:/anilist: meta ids (kitsu: ids NOT checked — FACT); port the same limitation, don't "fix" it into a divergence.
- Unaired-episode filtering: honor Harbor's date validation (spec §24 — no playing unaired episodes).

## 3. Ratings stack (per card and detail — parity-critical #3)

Layered, each independently keyed/optional — a missing key silently drops that tier (port exactly):

```
Cinemeta/IMDb (meta.imdbRating)
 → OMDB (IMDb/RT/Metacritic + Certified Fresh ≥75% & ≥50k votes + awards)
 → MDBList (Letterboxd / Trakt / RT-audience / Simkl)
 → harbor-imdb (episodes, anime)
 → TVDB thumbs
```

Keys: `tmdbKey, omdbKey, mdblistKey, fanartKey, tvdbKey, rpdbKey` — all user-provided, Keychain-stored.

## 4. Awards (parity-critical #4)

- Non-anime: Wikidata SPARQL (P345/P166/P1411) + OMDB `Awards` string regex + **bundled static award-history JSON** (title + person inverted indexes).
- Anime: bundled datasets + **franchise-key string matching** — normalize title → strip season/part/sequel suffixes → exact key lookup, with a Jikan-resolved synonym cache. Badges: Crunchyroll Awards, TAAF, JMAF, r/anime, Animation Kobe (icons with specific CSS filters — port as tinted SF Symbols/assets).
- Award browse pages: seeds from history (top films ≤300, actors 18, directors/writers 14 by wins) resolved via TMDB search.

## 5. Anime providers (port)

Kitsu API (rate-limited), AniZip, Jikan (MAL), AniList GraphQL, MAL REST v2, anime-lists (anidb↔imdb map), TVDB thumbs, AniSkip v2 (via skip-intro), streaming availability per region (Crunchyroll/Netflix/etc.), anime-franchise-episodes (root + relations).

## 6. Sync integrations (port — OAuth flows via ASWebAuthenticationSession)

- **AniList**: OAuth2 code+PIN (`/oauth/pin`), GraphQL `SaveMediaListEntry`, auto CURRENT→COMPLETED, per-profile sent-guard.
- **MAL**: OAuth2 PKCE plain, `/v2` REST, `my_list_status` PATCH, auto plan_to_watch→watching.
- Harbor's token-exchange proxies (harbor.site) hide provider secrets — iOS needs its own client registrations (documented: requires user-created API keys for some providers; where Harbor proxies are unusable, mark the feature as requiring user key).
- Progress markers, avatars, "Your AniList/MAL" rails, watched maps.

## 7. Anime UI (rooms-ui parity)

- Anime hero (CinemaHero-style), genre/era rows, seasonal, top airing, franchise browsing, "Your AniList" rails, award rows, dub/sub badges, anime Continue Watching.
- Discover personalization: anime metas contribute genres+decade only (no cast ids — FACT).

## 8. Windows-testable

Kitsu↔MAL↔Simkl mapping chains, episode numbering logic, award title normalization + franchise-key matching, AniZip/Jikan response mapping, anime stream enhancer (anitomy rules), batch detection. Golden vectors in `scripts/parity/`.
