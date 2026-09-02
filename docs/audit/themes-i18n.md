# Harbor v0.9.21 — Forensic Report: Themes, Theme Studio, i18n, RTL/Arabic

**Repo inspected:** `C:/Users/Admin/AppData/Local/Temp/harbor-ref`
**Date:** 2026-09-02 · **Scope:** complete theming subsystem, custom-code execution, import/export, i18n, RTL, Arabic, chrome variants.
All findings are from code inspection; every claim carries a file path. A FACT vs INFERENCE section closes the report.

---

## 1. Architecture map

| Concern | Primary files |
|---|---|
| Theme model + presets + apply pipeline | `src/lib/theme.ts` (1759 ln) |
| User/custom theme CRUD + JSON parse/export | `src/lib/custom-themes.ts` |
| Foreign format importers | `src/lib/theme-import/{index,color-math,project-palette,parse-base16,parse-kodi,parse-spicetify}.ts` |
| `.harborstyle` text format | `src/lib/harborstyle.ts` |
| Custom CSS/HTML/JS mounting (runtime) | `src/components/custom-code-mount.tsx` |
| Theme Studio UI | `src/views/settings/theme-panel/theme-studio.tsx` + `theme-studio/*` (≈30 files) |
| Settings theme panel | `src/views/settings/theme-panel.tsx`, `color-theme-body.tsx`, `custom-themes-section.tsx`, `display-section.tsx`, `background-picker.tsx`, `font-grid.tsx`, `logo-picker.tsx`, `custom-editor.tsx` |
| Background image persistence | `src/lib/theme-storage.ts` (IndexedDB) |
| Community store API | `src/lib/theme-store.ts` (`https://harbor.site/themes/api`) |
| Chrome variants | `src/chrome/{sidebar,siderail,stremio-rail,topdock,cinematic-overlay,minui-dock,royal-topbar,dracula-sidebar,nord-sidebar,forest-sidebar,custom-layout-safety-net}.tsx` |
| i18n | `src/lib/i18n/index.ts` + `src/lib/i18n/locales/{en,ar,pt,ru}.json` |
| Arabic content rows | `src/lib/arabic/{rows,classics,home-rows,index}.ts` |
| String-level RTL/Arabic helpers | `src/lib/iptv/rtl.ts` |

---

## 2. Complete preset theme inventory (from code)

### 2.1 Built-in presets — `THEME_PRESETS` (src/lib/theme.ts:112–308) — 8 themes

**Themeable token set is identical for every theme: 12 CSS custom properties** (canvas, surface, elevated, raised, ink, ink-muted, ink-subtle, edge, edge-soft, accent, accent-soft, danger). Colors below are the defining `--color-canvas / --color-accent` + layout/card/button style.

| # | id | Name | Canvas | Accent | Layout | Card | Button | Font pair | Notes |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `cool-grey` | **Harbor default** | `oklch(0.18 0.004 260)` | `oklch(0.78 0.13 60)` (amber) | *(fallback sidebar)* | flat (fallback) | flat (fallback) | sentient-switzer | Ships out of the box; tokens defined in oklch |
| 2 | `nord` | **Nord** | `#2e3440` | `#88c0d0` | `nord` | — | — | — | Hex Nord palette |
| 3 | `stremio` | **Stremio** | `#0c0b11` | `#7b5bf5` | `stremio` | `stremio` | — | plus-jakarta | Purple accent; gradient background `linear-gradient(41deg,#0c0b11,#1a173e)` dim 0; ink in rgba white |
| 4 | `crunch` | **Crunchy** | `#000000` | `#ff640a` | `topdock` | `crunch` | `crunch` | plus-jakarta | Spice-orange accent |
| 5 | `tokyo-night` | **Royal** *(id says tokyo-night, display name Royal)* | `#0c1118` | `#f08032` | `royal` | — | — | — | Deep navy + warm orange |
| 6 | `dracula` | **Dracula** | `#282a36` | `#bd93f9` | `dracula` | — | — | — | |
| 7 | `forest` | **Forest** | `oklch(0.18 0.018 145)` | `oklch(0.80 0.15 145)` | `forest` | — | — | — | Green oklch ladder |
| 8 | `noir` | **Noir** | `#000000` | `#ffffff` | `topdock` | `noir` | `noir` | general-sans | Pure black |

### 2.2 Beta themes — `BETA_THEMES` (src/lib/theme.ts:1395–1453) — 2 themes
"Experimental 1:1 ports" (see `beta-themes-modal.tsx`) shipping **full custom css/html/js strings**:

- **ElegantFin** (`elegantfin`) — port of lscambo13's Jellyfin theme. Dark navy glass, purple `#775bf4` accent, `layout: sidebar`, `cardStyle: glass`, `buttonStyle: flat`, `fontPair: fraunces-inter`. `css` = `elegantFinCss` (~640 lines of raw CSS targeting Harbor DOM: `aside[data-harbor-sidebar]`, `.harbor-search-pill`, `.harbor-poster`, `.harbor-bleed-stremio`, player progress, etc.); `html` = fixed overlay with `#ef-topleft` hamburger cluster + `#ef-scrim`; `js` = `elegantFinJs` IIFE (drawer toggle, DOM patching, `window.__harborThemeCleanup` cleanup contract, 800 ms interval tick).
- **Feishin** (`feishin`) — port of the Feishin player. Near-black ladder, electric blue `#3574FC`, `layout: custom`, `cardStyle: flat`, 5px corners. `css` = `feishinCss` (gated on `html[data-theme-layout="custom"]`, `.fsh-rail` fixed 240px rail, etc.); `html` = `feishinHtml` (`<aside class="fsh-rail">` with nav buttons calling `window.harbor.navigate(...)`); `js` = `feishinJs` (MutationObserver for active nav sync, `window.__harborThemeCleanup`).

### 2.3 Featured custom themes — `FEATURED_CUSTOM_THEMES` (src/lib/theme.ts:1455–1516) — 2 themes
- **Aurora** (`aurora`) — liquid glass / Frutiger Aero. Canvas `#06112a`, accent `#7cd6ff`; `layout: topdock`, `cardStyle: glass`, `buttonStyle: glossy`, **`bokeh: true`**; dual radial-gradient background (blue→indigo), dim 0; `aurora.png` preview.
- **MinUI** (`minui`) — the only **light** theme. Canvas `#f6f6f7`, ink `#0a0a0c`, accent `#0d7c66`; `layout: minui`, `cardStyle: minui`, `buttonStyle: minui`; radial white gradient; `fontPair: general-sans`; `minui.png` preview.

### 2.4 Templates — `TEMPLATE_THEMES` (src/lib/theme.ts:1518–1549) — 1 theme
- **Velvet** (`velvet`) — eggplant + champagne gold `#d4b562` + serif. `layout: rail`, flat card/button, radial gradient background, `sentient-switzer`, `velvet.png` preview. Promoted to "Built-in" category in the library UI (`PROMOTE_TO_BUILTIN = {"velvet"}`), while `crunch` is promoted to "Featured" (`PROMOTE_TO_FEATURED = {"crunch"}`, src/views/settings/theme-panel/custom-themes-section.tsx:197–198).

### 2.5 Resolution & totals
- `getThemeById()` (theme.ts:1663) searches `THEME_PRESETS` → featured → beta → templates → `user:*` themes.
- **13 shipped themes total in code** (8 built-in + 2 beta + 2 featured + 1 template), plus unbounded `user:` themes.
- `nextColorTheme()` (theme.ts:1681) cycles the 8 built-ins for the keyboard color-cycle shortcut and **excludes `crunch`**.
- Preview PNGs: `src/assets/theme-previews/*.png` (aurora, crunchy, dracula, forest, harbor, minui, noir, nord, royal, stremio, velvet — 11 files).

---

## 3. Theme model — what is themeable

### 3.1 Per-theme fields (`ThemePreset`, src/lib/theme.ts:79–102)
1. **Colors — 12 tokens** (mandatory, validated on import): `--color-canvas`, `--color-surface`, `--color-elevated`, `--color-raised`, `--color-ink`, `--color-ink-muted`, `--color-ink-subtle`, `--color-edge`, `--color-edge-soft`, `--color-accent`, `--color-accent-soft`, `--color-danger`. Any CSS color syntax accepted (`#hex`, `rgb()`, `hsl()`, `oklch()`, `color()`, per `isColor` in custom-themes.ts:7). Tailwind 4 `@theme` maps these to `bg-canvas`, `bg-surface`, `bg-elevated`, `bg-raised`, `text-ink`, `border-edge`, `bg-accent`, etc. (src/index.css:10–27).
2. **Background** (`ThemeBackground`): `image` — either a CSS gradient string (`linear-gradient(...)`, `radial-gradient(...)`, `conic-gradient(...)`) or an image URL/data-URL; optional `dim` 0–1 overlay. (theme.ts:50–53)
3. **Logo** (`ThemeLogo`): `wordmark` and `mark` (data-URLs, typically SVG). (theme.ts:55–58)
4. **Layout** (`ThemeLayout`, theme.ts:24–35): `sidebar | topdock | rail | stremio | minui | dracula | nord | forest | royal | cinematic | custom` — 11 chrome variants.
5. **Card style** (`ThemeCardStyle`): `flat | glass | stremio | minui | crunch | noir | custom` — implemented via `html[data-theme-card=…]` selectors in index.css (glass at 1416, minui at 1427, etc.).
6. **Button style** (`ThemeButtonStyle`): `flat | glossy | minui | crunch | noir | custom` — `html[data-theme-button="glossy"]` block at index.css:1492.
7. **Bokeh** (bool) — animated floating orbs (`AuroraBokeh`, src/components/theme-backdrop.tsx + src/components/aurora-bokeh.tsx), `data-theme-bokeh=on/off`.
8. **Chrome config** (`ChromeConfig`, theme.ts:71–77): `position: "sidebar" | "topbar"`, `brand` string, `items: ChromeNavId[]` (home, movies, shows, anime, library, live, discover, calendar, settings), per-item `labels` and `icons` overrides.
9. **Nav customization** (`navCustomization`): `order`, `hidden`, `renamed` maps — applied via `applyNavCustomization(NAV_ITEMS, …)` (src/chrome/nav-items.tsx).
10. **Typography**: `fontPair` (7 built-in pairs, §3.2) + `customFontId` (uploaded font, injected as `"harbor-font-<id>"` at the head of `--font-display`/`--font-sans`, theme.ts:1709–1712).
11. **Custom code**: `css`, `js`, `html` strings (beta themes + user themes only).

### 3.2 Font pairs (`FONT_PAIRS`, theme.ts:1551–1601)
sentient-switzer (default), fraunces-inter, general-sans, cabinet-switzer, plex (IBM Plex Sans), plus-jakarta, system. Applied by setting `--font-display` and `--font-sans` on `<html>`. (`--font-channel`, `--font-anime`, `--font-mono` exist in `@theme` but are not per-theme settings.)

### 3.3 NOT part of the theme object (app-level settings adjacent in the Theme panel)
- **Player seek bar**: `seekBarStyle: flat|glass|pinstripe|rainbow|image`, `seekBarHeight`, `seekBarColor`, `seekBarImage`, `seekBarFill`, `seekBarFillOpacity`, `seekDotShape: circle|square|image|hidden`, `seekDotSize`, `seekDotImage` (src/lib/settings/types.ts:378–386; `SeekBarPanel` in settings).
- **Poster sizing**: `posterScale`, `posterRadius` + liquid-glass blur/tint (`display-section.tsx`).
- **User wallpaper**: `theme.backgroundImage` / `backgroundDim` are `ThemeSettings` fields (theme.ts:1616–1623), separate from the per-preset background; persisted in **IndexedDB** (`harbor-theme`/kv, key `bg`, src/lib/theme-storage.ts) with legacy localStorage key migration (`harbor.theme.bg`); processed by `image-utils.ts` (downscale ≤3840px, JPEG quality ladder 0.85→0.25, ≤8 MB).
- **Custom colors ("Custom" tile)**: `customColors: CustomColors` (10 fields: canvas, surface, elevated, raised, ink, inkMuted, inkSubtle, edge, accent, danger — no `accent-soft`, it is derived: `${accent}2e`; edge-alpha derived: `${edge}8c`/`40`), legacy editor `custom-editor.tsx`; converted to tokens by `customColorsToTokens()` (theme.ts:1646).
- Global custom code: `settings.customCss / customJs / customHtml` (types.ts:387–389) — the same injection machinery as theme code.

### 3.4 Application pipeline
`applyTheme(theme)` (theme.ts:1701–1724):
1. Resolve 12 tokens (custom colors, preset tokens, or cool-grey fallback) → `document.documentElement.style.setProperty(...)`.
2. Set `--font-display`/`--font-sans` (custom font first if set).
3. Set `data-theme-layout`, `data-theme-card`, `data-theme-button`, `data-theme-bokeh` on `<html>`.
index.css then implements the visual treatments keyed off those attributes. `ThemeBackdrop` (components/theme-backdrop.tsx) renders background image/gradient + dim overlay + bokeh; preset gradients get dim 0 (no extra black veil), user images get a fixed 0.45 black veil + dim overlay.

---

## 4. Custom code: injection, execution, and the sandbox question

**File:** `src/components/custom-code-mount.tsx` (97 ln) — single mount point for both app-level custom code and theme code (`themeExt` = active preset's `css/js/html`, resolved via `getThemeById`; skipped when preset is `"custom"` legacy colors).

Injection (facts):
- **CSS**: `document.createElement("style")` with id `harbor-custom-css` (app) and `harbor-theme-css` (theme); `el.textContent = code`. Appended to `<head>` AFTER app styles → later stylesheet wins ties; theme CSS is raw/unanchored so `!important` + any selector works (the ElegantFin css comment says exactly this: "Injected raw into `<style id="harbor-theme-css">` so !important + any selector wins").
- **JS**: executed by `new Function(code)()` inside try/catch; errors only `console.warn("[harbor-theme-js] error:")`. Runs in the **main renderer global scope with full `window`/`document` access**.
- **HTML**: `<div id="harbor-custom-overlay" aria-hidden class="pointer-events-none fixed inset-0 z-[100]">` with `dangerouslySetInnerHTML={{__html}}`. The wrapper is `pointer-events-none` but **child elements are free to re-enable `pointer-events`** (ElegantFin's `#ef-topleft { pointer-events: auto }` does exactly that), and it is hidden (`hidden` class) while the player is open. Studio preview additionally filters: HTML overlay is only mounted when `draft.layout === "custom"`.
- **Cleanup contract**: on theme/app-code change, `runThemeCleanup()` invokes `window.__harborCustomCleanup` / `window.__harborThemeCleanup` if present (custom-code-mount.tsx:11–22). Bundled beta themes implement `__harborThemeCleanup` (remove listeners, clear intervals, detach observers, remove injected nodes).
- **Bridge API for generated chrome**: `window.harbor = { navigate(v), back(), search() }` defined in `src/App.tsx:808–816`; generated custom-chrome HTML (`chrome-config.ts` `buildChrome`, Feishin html) calls it via inline `onclick`.

**Sandboxing: NONE.** There is no iframe, no worker, no proxy/realm, no capability allowlist, no code transformation, and no permission prompt at execution time. Theme JS executes with the same privileges as the app bundle itself (it can read localStorage, call `window.harbor`, touch the DOM, invoke any global). The only containment is convention (cleanup functions) and a safety net for a specific failure mode: `src/chrome/custom-layout-safety-net.tsx` — for `layout: "custom"` themes App.tsx renders no nav chrome at all (it trusts the theme's injected HTML); if no `[data-harbor-nav]` element exists 1.2 s after mount (theme JS threw / HTML never landed, cf. issue #951), the safety net renders a minimal escape-hatch menu with max z-index, and re-appends its stylesheet on every activation to stay last in `<head>`.

**CSP tension (verify):** `src-tauri/tauri.conf.json` declares
`"csp": "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src ...; connect-src ...; object-src 'none'; frame-src 'none'; base-uri 'self'"`.
`script-src 'self'` contains **no `'unsafe-eval'`**, and `new Function` is governed by the eval policy. If this CSP is enforced in the production webview, theme/app JS (`new Function`) and inline `onclick` handlers in injected HTML would be blocked (EvalError), which would break ElegantFin, Feishin, every custom-chrome theme, and the app's own customJs feature. The feature is clearly designed around `new Function` working, so either the CSP is not applied in the build this ships with (e.g. dev builds, or Tauri CSP injection disabled) or the feature silently no-ops — **parity-critical behavior #1 to verify against the real binary** (see §11).

---

## 5. Theme Studio (`src/views/settings/theme-panel/theme-studio.tsx`)

Entry: "Open Studio" hero card in Settings → Theme → "Your themes" (`custom-themes-section.tsx` → `HeroCards`). Renders as a full-screen portal with a 440px right-side inspector (`z-[210]`, `createPortal(document.body)`).

**Live preview mechanics:**
- On open, `useStudioPreview` (theme-studio/hooks/use-studio-preview.ts) forces `setView("home")` so the live app becomes the canvas, and publishes `{layout, bokeh}` through `src/lib/theme-preview.ts` (external store consumed by `ThemeBackdrop`). On close: `setThemePreview(null)`, view back to `settings`, and the previous real theme is re-applied from a ref.
- Every draft change re-runs `applyTheme` with the draft colors + font pair + custom font; data-attributes are set directly (`theme-studio.tsx:153–167`).
- Draft CSS is hot-injected into `style#harbor-studio-preview-css` (live as you type).
- Draft colors are also pinned via an "authority" stylesheet `#harbor-studio-authority-css` containing `:root:root { --color-…: … !important; }` so theme CSS can't clobber the palette while editing.
- Draft HTML mounts into a `pointer-events-none` fixed overlay (`z-59`) **only when layout is `custom`** (`theme-studio.tsx:192–201`).
- JS is NOT auto-run while editing — an explicit **Run** button (`runJs`, `new Function`) exists in the JS tab of the code editor.

**Editor tabs (Inspector, theme-studio/inspector.tsx):**
- **Look**: Identity (name/blurb/seed-from-preset), **Colors** (`ColorsGrid` — 10 color inputs + `StyleSpecimen` live swatch strip), **Cards** (`StylePicker` 7 styles + optional `CardCssPopout` for hand-tuned card CSS), **Buttons** (`StylePicker` 6 styles), **Typography** (`FontPicker` 7 pairs + uploaded fonts via `custom-font-tiles`), **Ambience** (bokeh toggle).
- **Layout**: `LayoutPicker` with 7 options and SVG diagrams — Sidebar ("wide left bar with labels"), Top dock ("floating top pill"), Side rail ("narrow icon-only column"), Stremio rail, Floating dock ("macOS-style bottom dock" = minui), Cinematic ("immersive floating overlay nav"), Custom ("write your own chrome with HTML + CSS"). For non-custom layouts: `NavEditor` (reorder/rename/hide nav items, `nav-row.tsx`). For `custom`: `CustomChromeBuilder` — position sidebar/topbar, brand text, item checklist, per-item label + icon (`icon-picker.tsx`, `chrome-icons.ts` lucide-name→SVG lookup, data-URL support); `buildChrome()` (chrome-config.ts:149) generates the theme's `html` + `css`; dirty-tracking prevents regenerating over hand-edited code; "Regenerate" button restores generated output.
- **Code**: CSS/HTML/JS. `CodePopout` opens a full-screen editor (`z-[230]`, one-dark style, `components/code-editor` `CodeEditor`) with: file tree (3 virtual files with sizes), tabs, copy, per-file download, caret line/col status bar, **Cheat sheet** (documented selectors/recipes: `cheat-sheet.tsx`, `cheat-sheet-data.ts`, `cheat-sheet-recipes.ts`, `cheat-sheet-parts.tsx` — a catalog of Harbor DOM hooks like `.harbor-poster`, `[data-harbor-nav]`, `#harbor-custom-overlay`, etc.), undo/redo, and the Run button for JS.

**Editing ergonomics:** draft history undo/redo (120 entries, 450 ms coalescing, `hooks/use-draft-history.ts`), Ctrl/Cmd+Z / +Shift+Z, Ctrl/Cmd+P toggles inspector visibility, ESC closes (with a dirty-state "Leave without saving?" confirm). Discord Rich Presence activity hint while designing. Seeding from any preset/theme creates a "<Name> copy" draft with tokens flattened to hex via a 2D-canvas color parser.

**Save / Export:** Save → `saveCustomTheme()` (new `user:<slug>-<base36>` id) and immediately activates it; Export → `serializeHarborStyle()` downloaded as `<slug>.harborstyle`.

---

## 6. Import / export / duplicate / delete / storage

**Storage:** all custom themes in one `localStorage` key — `harbor.custom-themes.v1` (JSON array, custom-themes.ts:3). In-memory cache + subscriber set (`useSyncExternalStore`-style). Validation on load (`isCustomTheme`): `id` must start with `user:`, non-empty name, 3-string swatch, all 12 tokens present as strings. **No size quota handling** — themes embed arbitrary css/js/html and image data-URLs in a single localStorage key (5–10 MB typical quota), a real failure mode for big community themes (see §11). Background images go to IndexedDB separately (§3.3). Community uploads' owner tokens live in `harbor.theme-uploads.v1`.

**Formats:**
1. **Native JSON** (`parseThemeJson`): strict — swatch must be 3 `#hex`, every token must pass the color regex (hex/rgb/hsl/oklch/oklab/color()); unknown fields dropped; length caps (name 60, blurb 160, labels ≤300k?? — actually `parseNavMap` caps label strings at 300000 chars and nav ids at 64).
2. **`.harborstyle`** text format (src/lib/harborstyle.ts): manifest `key: value` lines (`name`, `blurb`, `layout`, `card`, `button`, `font`, `bokeh`, `swatch: #a,#b,#c`, `bg-image`, `bg-dim`, `logo-wordmark`, `logo-mark`, `chrome-position`, `chrome-brand`, `chrome-items`) + `@tokens` / `@css` / `@html` / `@js` blocks; parsed to JSON then validated by `parseThemeJson`. Export path is always `.harborstyle` (`serializeHarborStyle`); a plain-JSON exporter (`exportThemeJson`) also exists in custom-themes.ts.
3. **Foreign imports** (`src/lib/theme-import/index.ts:46` `importForeignTheme`): **Base16** YAML/JSON (base00–base0F/base11 slots, light/dark variant detection), **Spicetify** `color.ini` (multi-scheme → multiple themes), **Kodi** skin colors XML (`<color name=…>abc0def0</color>`). Palettes are projected onto the 12-token ladder by `project-palette.ts` using the local color-math library (`color-math.ts`: hex/rgb/hsl/oklch parse, chroma, relLum, lighten/darken/mix, isLight, isRedHue — no external dependency). **ZIP is explicitly rejected** ("Zipped themes aren't supported yet", custom-themes-section.tsx:63). File-picker accept list: `.harborstyle,.json,.txt,.harbortheme.json,.yaml,.yml,.ini,.xml`.
4. **Community store** (`src/lib/theme-store.ts`, `https://harbor.site/themes/api`): browse (sort=top/new, search q), download (fetches theme file → `parseThemeJson` → saved locally), rate (anonymous 24-hex `clientId` in localStorage), upload (multipart `theme` JSON + `cover` + ≤6 `screenshots` + author; returns `ownerToken`), visibility (public/unlisted) and delete via owner token; unseen-download badges (`harbor.theme-unseen.v1`). UI: `community-browser.tsx`, `community-detail.tsx`, `theme-upload-flow.tsx` (cover cropper, listing preview).

**Duplication:** no explicit "duplicate" button; duplication = Theme Studio "seed from theme" (creates `<Name> copy` draft) → Save as new `user:` id. Deleting a user theme that is active falls back to `cool-grey` (custom-themes-section.tsx:110–115). Library view (`library-browser.tsx`/`library-grid.tsx`) groups: Built-in / Featured / Template / Yours, with export-copy block (`export-block.tsx`), per-theme download, and remove (user themes only).

---

## 7. i18n subsystem

**File:** `src/lib/i18n/index.ts` — dependency-free custom catalog (no i18next/react-intl). **4 languages**: English (en, 4644 keys), Arabic (ar, 3733 keys), Portuguese (pt, 4561 keys), Russian (ru, 4638 keys). JSON catalogs at `src/lib/i18n/locales/*.json` (17.5k lines total).

- API: `t(key, vars)` with `{placeholder}` interpolation, `useT()` hook, `useUiLanguage()`, `setUiLanguage()`, `sourceTranslationKey(value)` (reverse lookup used by settings).
- Resolution: `normalizeLanguage` / `detectUiLanguage` (walks `navigator.languages`, strips region/script/extension subtags) / `resolveUiLanguage(stored, preferred)`. Stored value is read **per profile**: parses `harbor.profiles.v1` → active profile id → `harbor.settings.<id>` (if `settingsLinked === false`) else `harbor.settings.shared` (i18n/index.ts:95–116).
- Fallback chain: current language → English → raw key. **Arabic has 911 keys missing vs English** (measured) — those strings render in English inside the Arabic UI.
- `setUiLanguage`/init writes `document.documentElement.lang` and `dir`.

**RTL handling:**
- `directionForLanguage(lang)`: 4-letter script subtags (`adlm, arab, hebr, nkoo, rohg, syrc, thaa`) → rtl; else language list (`ar, arc, ckb, dv, fa, he, nqo, ps, sd, syr, ug, ur, yi`) → rtl. Applied as `document.documentElement.dir`.
- UI components use Tailwind logical properties (`ms-`, `me-`, `start`, `end`, `text-start`) and explicit `rtl:` variants (55 files use `rtl:…`, e.g. `translate-x-full rtl:-translate-x-full` in the studio panel; `translate-x-5 rtl:-translate-x-5` toggles). `index.css` carries `[dir="rtl"]` blocks (≈2511+; icons, animations, crunchy profile dropdown).
- **Arabic shaping library: NONE.** No arabic-reshaper, ar.js, bidi, harfbuzz, or intl-segmenter usage anywhere in `package.json` or `src/`. Text shaping is delegated entirely to the browser/OS text engine (WebKitGTK/WebView2/WKWebView). The only Arabic-specific code is:
  - `src/lib/iptv/rtl.ts` — string-level detection/`normalization`: RTL_RANGE/ARABIC_RANGE/HARAKAT regexes, `isRtl(s)`, `dirOf(s)`, `hasArabic(s)`, `normalizeArabic` (strips harakat, unifies alef variants أإآٱ→ا, ة→ه, ى→ي, ؤ→و, ئ→ي), and `arabicAwareMatch` (search fallback used by `src/lib/search.ts` for channel search).
  - `isRtl(useUiLanguage())` used by `hero-carousel.tsx` and `forest-sidebar.tsx`; `isRtl(el)` scroll-direction math in `media-rail.tsx`.

**The `src/lib/arabic/*` subsystem is NOT text/RTL infrastructure — it is Arabic *content*:** 7 TMDB-driven home rows (`rows.ts`): Ramadan (2025/2026 cycles), Arabic Drama, Arabic Movies, Khaleeji (Gulf countries `SA|AE|KW|QA|BH|OM`), Arabic Comedy, Trending in Arabic (18-month window), plus Egyptian Cinema Classics (`classics.ts` — 10 hardcoded titles, e.g. Cairo Station 1958). All queries `language=ar-SA` + `with_original_language=ar`; rows build only when a TMDB API key is configured (`buildArabicHomeRows` returns `[]` without key, `home-rows.ts`). Row titles use i18n keys `arabic.row.*`.

---

## 8. Chrome variants (`src/chrome/*`) and layout mapping

App.tsx (lines 995–1019) maps `activeLayout(settings.theme)` (or studio preview layout) to a concrete chrome component; all variants consume `NAV_ITEMS` + `applyNavCustomization` (nav-items.tsx) and hide when `chromeHidden` (player/immersive):

| Layout | Component | Notes |
|---|---|---|
| `sidebar` | `chrome/sidebar.tsx` (370 ln) | Default: wide left bar `data-harbor-sidebar`, Harbor logo (per-theme logo mark/wordmark via `useHarborLogo`), profile chip, collapse toggle, kids doodles mode |
| `dracula` | `chrome/dracula-sidebar.tsx` | Themed sidebar variant |
| `nord` | `chrome/nord-sidebar.tsx` | Themed sidebar variant |
| `forest` | `chrome/forest-sidebar.tsx` | Themed sidebar variant (RTL-aware) |
| `stremio` | `chrome/stremio-rail.tsx` (197 ln) | Narrow icon rail, cat avatar, per-theme logo mark |
| `topdock` | `chrome/topdock.tsx` (1032 ln) | Floating top pill; plus `FloatingBack` (offset 92) |
| `cinematic` | `chrome/cinematic-overlay.tsx` (272 ln) | Immersive floating overlay nav + compact profile chip; plus `FloatingBack` |
| `royal` | `chrome/royal-topbar.tsx` | Royal topbar; plus `FloatingBack` |
| `rail` | `chrome/siderail.tsx` (246 ln) | Narrow icon-only column, profile block |
| `minui` | `chrome/minui-dock.tsx` (151 ln) | macOS-style bottom dock, hover magnification (54px base, 1.42× peak, 140px range), `DockButton`, `FloatingTop` |
| `custom` | **no React chrome** | Theme supplies 100% of nav via injected HTML/CSS/JS (CustomCodeMount); `custom-layout-safety-net.tsx` escape hatch (§4) |

Shared chrome: `nav-items.tsx`, `nav-overflow.tsx`, `back-chrome.tsx`/`floating-back.tsx`, `window-controls.tsx`, `window-resize-edges.tsx`, `hover-nav-icon.tsx`, `offline-banner.tsx`, `recording-pill.tsx`, `topbar.tsx` (TogetherButton/RecordingPill shared). Layout also gates CSS: `html[data-theme-layout="rail"]`/`"stremio"`/`"minui"` blocks in index.css adjust `main` padding and card surfaces.

---

## 9. Settings surface (theme-related fields)

`src/lib/settings/types.ts` → `Settings.theme: ThemeSettings` (line 331; `{preset: ActiveThemeId, backgroundImage, backgroundDim, fontPair, customFontId, customColors}`), defaults from `DEFAULT_THEME` (theme.ts:1638: cool-grey, dim 0.65, sentient-switzer). Related settings: `navCustomization` (360–364), `customCss/customJs/customHtml` (387–389), seek-bar fields (378–386), `posterScale/posterRadius` + `defaultLiquidGlassBlur/Tint` + `experimentalLiquidGlassEnabled`, `customLogoMark/customLogoWordmark/customAppIcon` (332–334), `customFonts` (via `useCustomFonts`, `font-storage.ts`, ≤32 MB per font, ttf/otf/woff/woff2), `uiLanguage` (460), `useNativeTitleBar`, `playerChromeTheme: auto|default|stremio` (195; `resolveChromeTheme` maps stremio layout → stremio player chrome, theme.ts:1731). `applyCustomColorsPreview` exists for the legacy color editor live preview. `soundTheme` (none|glass|modern|retro|cinematic) is unrelated to visual themes.

---

## 10. FACT vs INFERENCE

**FACT (directly observed in code):**
- 13 shipped themes; 12-token palette; 11 layouts; 7 card styles; 6 button styles; 7 font pairs; 4 languages.
- Custom JS runs via `new Function` with full renderer scope; HTML via `dangerouslySetInnerHTML`; CSS via raw `<style>` — **no sandbox of any kind in application code**.
- Theme storage = single localStorage key per theme set; background images in IndexedDB; no quota handling in code.
- ar.json is 911 keys short of en.json; fallback is English strings.
- No Arabic shaping library; browser-native shaping only; `arabic/*` is TMDB content rows.
- Tauri CSP declares `script-src 'self'` (no `unsafe-eval`) while the app executes `new Function`.

**INFERENCE (needs runtime verification):**
- Whether the declared CSP is actually enforced in the production webview. If it is, `new Function` (and inline onclick in injected HTML) throws and custom-code themes break; if the app works as designed, the CSP must not be in effect — either way the shipped behavior must be tested against the real binary (parity-critical).
- localStorage persistence of huge theme payloads (data-URL logos, multi-KB css/js) may exceed quota on import of several community themes; the code catches write errors silently (`writeRaw` swallows exceptions) so themes can silently fail to save.
- Browser-native Arabic shaping quality/ligature fidelity is platform-dependent (WebView2 vs WKWebView vs WebKitGTK) and unverifiable statically.
- `theme-panel.tsx` shows a seek-bar section inside the Theme panel — it is settings-scoped, not per-theme; a port that expects seek bar styling to ride along with themes would diverge.

---

## 11. Top parity-critical behaviors for a reimplementation

1. **Custom-code execution model with zero sandbox** — CSS/HTML/JS from themes runs at app privilege (`new Function`, `dangerouslySetInnerHTML`, raw `<style>`, `window.harbor` bridge at App.tsx:810). Any port must reproduce the *capabilities* (themes depend on DOM selectors like `[data-harbor-nav]`, `.harbor-poster`, `[data-harbor-sidebar]`, injected overlay layers z-59/z-100) — while ideally sandboxing. The `__harborThemeCleanup`/`__harborCustomCleanup` contract must exist or theme switching leaks listeners/intervals.
2. **Data-attribute theming contract** — themes are applied as `data-theme-layout/card/button/bokeh` + 12 CSS vars on `<html>`; the entire visual treatment lives in index.css selectors. Ports must keep the same attribute names and token names (incl. `--color-accent-soft` derivation and oklch support) or every preset + every community theme renders wrong.
3. **Layout→chrome mapping** (sidebar/dracula/nord/forest/stremio/topdock/royal/rail/minui/cinematic/custom) — `custom` renders NO app chrome and trusts injected HTML, with the 1.2s `[data-harbor-nav]` safety-net detection as the only recovery path. Losing the safety net reproduces the "no menus" brick (#951).
4. **Import format strictness** — JSON validation demands all 12 tokens + 3-hex swatch; foreign importers (Base16/Spicetify/Kodi) project palettes via a custom color-math pipeline; `.harborstyle` has a distinct block syntax. Duplicate-import behavior (new `user:` id each time) and delete-active→cool-grey fallback must match.
5. **i18n/RTL semantics** — `document.documentElement.dir` from script/language detection, per-profile language storage keys, 911-key Arabic fallback to English, logical-property + `rtl:` class usage, and browser-native (no-library) Arabic shaping — plus the Arabic *content* rows (TMDB ar-SA, key-gated) that live under the same "arabic" umbrella.
