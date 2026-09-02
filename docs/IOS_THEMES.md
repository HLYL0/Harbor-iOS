# IOS Themes

> Theme system + Theme Studio design (spec §33–35). Behavior source: `docs/audit/themes-i18n.md` (verified).

## 1. Theme inventory (13 shipped — port all)

| Category | Themes |
|---|---|
| Built-in (8) | cool-grey (Harbor default), Nord, Stremio, Crunchy, Royal (tokyo-night), Dracula, Forest, Noir |
| Beta (2) | ElegantFin, Feishin (ship full custom css/js/html strings — these are the code-bearing themes) |
| Featured (2) | Aurora (bokeh), MinUI (light) |
| Template (1) | Velvet |

Plus unbounded `user:` themes + community store.

## 2. Theme model (port the shape)

- **12 color tokens** (canvas, surface, elevated, raised, ink, ink-muted, ink-subtle, edge, edge-soft, accent, accent-soft, danger) — CSS color syntax accepted (hex/rgb/hsl/oklch/oklab/color()); custom-colors derive accent-soft/edge-alpha.
- Background: gradient string OR image/data-URL + dim 0–1. Logo: wordmark + mark. Bokeh bool. Chrome config (position/brand/items/labels/icons). Nav customization (order/hidden/renamed). Font pair (7 pairs + custom font upload). Custom css/js/html strings.
- Seek bar styling is **app-level settings**, not theme object (flat/glass/pinstripe/rainbow/image + height/color/dot shapes).
- iOS: tokens become Swift `Color`/`Font` resolution; backgrounds become native gradient/image renderers; bokeh = native particle overlay; seek bar styles = native player control styles.

## 3. Layouts → iOS navigation shells (11 layouts, native equivalents)

| Harbor layout | iOS shell |
|---|---|
| sidebar / dracula / nord / forest | iOS TabView sidebar-style shell w/ theme tint |
| stremio (rail) | TabView icon-only |
| topdock / royal | floating top pill (custom overlay) |
| cinematic | immersive overlay nav |
| minui | floating bottom dock |
| custom | custom chrome builder → native layout config (HTML chrome replaced) |

## 4. Custom code — THE security divergence (spec §35)

- **Harbor FACT: zero sandbox** — `new Function(code)()`, full window/document/localStorage access, no allowlist. On iOS we cannot and must not replicate that:
  - **CSS**: not applicable directly (no DOM) → token-level styling only; where a custom CSS targets a Harbor selector, map it to the equivalent SwiftUI modifier (documented mapping table).
  - **JS/HTML custom chrome**: **NOT EXECUTED on iOS** (BLOCKED — no privileged JS bridge; document in known limitations). Replaced by the native CustomChromeBuilder equivalent (position/brand/items/labels/icons).
  - If a user theme carries css/js/html, iOS imports tokens + layout only and shows a note. No arbitrary code execution, ever (spec §87).
- Beta themes ElegantFin/Feishin: imported as token sets + layout approximation, not their JS.

## 5. Theme Studio (native editor)

- Live preview on the actual app (SwiftUI live theme swap = trivial and better than Harbor's approach).
- Tabs: Look (colors grid + specimen, cards 7 styles, buttons 6 styles, typography 7 pairs + upload, ambience), Layout (picker with diagrams, NavEditor reorder/rename/hide, CustomChromeBuilder), Code (**not applicable** — replaced by advanced token editor).
- Undo/redo (120 entries), dirty-state confirm, seed-from-theme duplication, save → `user:<slug>-<base36>` + activate, export → `.harborstyle`.

## 6. Import/export formats (port — Windows-testable parsers)

1. Native JSON (strict: swatch 3-hex, all tokens valid colors, length caps, unknown fields dropped).
2. **`.harborstyle`** text format (manifest key:value + `@tokens/@css/@html/@js` blocks) — canonical export.
3. Foreign: **Base16** YAML/JSON, **Spicetify** color.ini (multi-scheme), **Kodi** skin XML — palette projection onto the 12-token ladder via color math (port color-math.ts). ZIP explicitly rejected (parity).
4. Community store (`harbor.site/themes/api`): browse/ download/ rate (anonymous id)/ upload + owner tokens/ visibility. iOS: browse+download+rate; upload requires the same API (optional).

## 7. i18n & RTL (spec §50, §98)

- **4 languages**: en / **ar** / pt / ru. Custom key catalog w/ `{placeholder}` interpolation + fallback chain → English → raw key.
- iOS: same 4 catalogs (String Catalogs), per-profile language setting. **Arabic has 911 missing keys upstream** — we port the same strings; missing keys fall back to English (parity) and can be completed as a contribution back upstream.
- **No JS shaping library in Harbor (FACT)** — the OS text engine shapes Arabic. On iOS CoreText does this natively and better: Arabic/RTL is inherently first-class.
- `normalizeArabic` (harakat strip, أإآٱ→ا, ة→ه, ى→ي, ؤ→و, ئ→ي) + `arabicAwareMatch` — port for search/EPG matching (already specified in IOS_LIVE_TV).
- **Arabic content rows** (spec §50): 7 TMDB-driven home rows (Ramadan, Arabic Drama, Arabic Movies, Khaleeji SA/AE/KW/QA/BH/OM, Arabic Comedy, Trending Arabic) + Egyptian classics — built only when a TMDB key is configured (parity). For LO's region these are core home content.

## 8. Fonts licensing

Font pairs (sentient, switzer, fraunces, inter, general-sans, cabinet, plex, plus-jakarta, system) — verify each font's license (OFL/paid) before bundling; replace paid fonts with OFL equivalents; record in THIRD_PARTY_LICENSES.md. Custom font upload → register via CTFontManager (app-scoped).
