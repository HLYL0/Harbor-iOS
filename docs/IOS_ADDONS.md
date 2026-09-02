# IOS Addons

> Addon manager + discovery store design. Behavior source: `docs/audit/stremio-addons.md` (verified).

## 1. Addon lifecycle (parity)

- Install (URL/manifest), uninstall, update, **reorder**, configure. Manifest fields consumed: `id, name, version, description, logo, background, contactEmail, catalogs[], resources[], types[], idPrefixes[], behaviorHints{adult, configurable, configurationRequired}`.
- Manifest validation: reject non-objects, missing/empty id/name, non-JSON, HTTP errors — specific error strings (parity).
- **Reorder**: port Harbor's 5-stage anti-corruption protocol — validate → refetch → drift-check → backup → write → read-back-verify. (Strongest corruption posture in the codebase; iOS must keep it.)
- Config UI: render from manifest `config` arrays (select/text/password, multi, required, defaults — same semantics as the addon SDK; see `stremio-addon-development` skill).
- Local copies slimmed (no secrets); account sync when signed in; degrade to local-only.

## 2. Discovery store (parity)

- **Primary**: stremio-addons.net API v0 — list (`limit 200, sort_by stars`), detail, categories (16 fallback entries), **rising** (24h stars). 1h TTL in-memory cache (max 48).
- **Fallback/merge**: Stremio's own catalogs (community.json, official.json, official-collection) fetched in parallel; failures → `[]`.
- Browse modes: top / rising / new. Search + category filter + nsfw exclusion.
- **Curated rails: EMPTY in v0.9.21 (FACT)** — don't build curation UI that Harbor itself doesn't populate.
- Ratings: **remote-only** (stars from stremio-addons.net; rate via site deep-link `#rate`). No client-side rating.
- Related/recommended addons: similarity scoring (category +50, tags +8, rails +6, type +4, resource +3) + taste boosts + adult parity.
- Velocity "movers" rail: star snapshots (14 max, ≥12h apart), delta ≥5.
- Normalized-name dedupe (brackets/suffixes/debrid words); always hide Harbor's own OpenSubtitles overlap.

## 3. Adult gating (parity + App Store compliance)

- `showAdultAddons` default **false**, behind an AgeGate modal.
- Classification: curated nsfw flag OR `behaviorHints.adult` OR ~180-term + ~70 word-boundary keyword matcher (leet/diacritic-normalized).
- When off: adult addons **deleted from the catalog entirely**; nsfw=exclude on API queries; adult parity in related addons.
- iOS: same logic + App Store 17+ rating (see `IOS_APPSTORE.md`).

## 4. Addon installer UX

- In-app installer for addons that need web configure screens: WKWebView, 7.5s timeout → paste-based fallback (Harbor's escape hatch, port it). JS off by default; config capture via URL redirect patterns.
- Install modal states: loading / error / success — same error strings.

## 5. Existing MVP → parity gap

| MVP has | Missing (this phase) |
|---|---|
| local install/remove, cloud sync | reorder w/ 5-stage guard, update flow, config UI, discovery store, adult gating, installer viewport, related addons |

## 6. Windows-testable

Manifest validation, resource-routing acceptance (`accepts()` — exists), config-array parsing, adult keyword matcher, normalized-name dedupe, reorder protocol state machine. All as Swift unit tests on CI + Python mirror where feasible.
