# IOS Stream Engine

> Canonical design for parse → trust → score → rank parity. Source of truth: `docs/audit/stream-engine.md` (every regex/weight/floor verified from code at commit `0117755`) + the vendored `rust/harbor-core` (56/56 tests green on Windows).

## 1. The critical architectural fact

Harbor Desktop runs TWO stream engines, and they have drifted apart:

| Path | Parsing | Trust/Score/Rank | When |
|---|---|---|---|
| **Tauri fast path** (what the desktop app actually uses) | **TS parser** (parse-torrent-title) | **Rust core** | desktop, always preferred |
| Web/browser fallback | TS | TS | web builds, core failures |

**Parity decision:** the iOS engine mirrors the **Tauri fast path semantics** — TS parser rules for parsing, Rust core semantics for trust/score/rank. Where TS≠RUST, we follow the Rust side (that's the shipped desktop behavior):

- primary selection **skips theater sources** (Rust) — TS doesn't
- any `url` counts as cached for ranking (Rust) — TS requires no uncached marker
- **no** `preferAac` (browser-only workaround) — Rust has no such parameter
- no LATAM/Latin-American Spanish special-casing (TS-only)
- no ElfHosted cache rule, no AIOStreams generic cache markers (TS-only)
- season-pack regex negative-lookahead semantics = Rust version
- TS-only source rules (TS/TC lookaheads, bare `WEB` fallback) — **excluded** (desktop parse path is TS actually — wait: parsing IS TS on desktop!).

**Correction on parsing:** the desktop fast path parses in **TS** (pipeline.ts), then hands parsed streams to Rust for trust/score/rank. So parsing parity = **TS parser semantics** (including its extra rules), and trust/score/rank parity = **Rust semantics**. Our engine: TS-parser-equivalent parsing (the TS parser is the runtime truth for desktop), Rust-equivalent trust/score/rank.

## 2. Engine shape

```
Swift StreamPipeline
 ├── ParseStage      (port of TS parser/*.ts + parse-torrent-title contract)
 ├── AnimeStage      (enhanceAnimeStreams — anitomy.ts, only when isAnime)
 ├── CacheStage      (live debrid cacheCheck/listLibrary + static cache flags)
 ├── TrustStage      (port of rust trust.rs — 23 rules, exact order)
 ├── CorpusStage     (compute_corpus_stats)
 ├── ScoreStage      (score_stream — exact deltas)
 ├── RankStage       (rank_and_pick — Rust semantics)
 └── RescueStage     (rescueCorroboratedLeaks — cinema-window false-positive recovery)
```

- **Golden vectors**: the 56 Rust tests + 17 TS fixture samples (documented in audit §7) are exported to JSON by a script in `scripts/parity/`; CI diffs Swift engine output against them. Every divergence must be justified in this file.
- **Vendored Rust crate** stays the reference: `rust/harbor-core` (cargo test on Windows). If drift between Swift port and Rust is ever unacceptable, the escape hatch is FFI-linking the crate (DR-003).

## 3. Parser parity (TS parser semantics)

Port exactly (audit §2): text assembly + `filename_score`, ptt_parse (title/year/season/episode/group/extended/uncut/proper/repack/remastered/unrated/criterion/codec/channels/bitdepth), resolution map, HDR detect (DV+HDR10 → DV → HDR10+ → HLG → HDR10), codec map, source detection (14 rules incl. TS extras), audio codec, channels/bitdepth, languages (word tokens + flag emoji + ISO pairs, incl. LATAM), size/seeders/container, edition, year range, disc, anime CRC `[A-F0-9]{8}`, scam score, **cache flags (two-phase deny-then-cached, all template-addon rules incl. AIOStreams generic + ElfHosted)**, episode title, season pack, release group + 51 trusted groups.

Swift implementation notes: regexes ported 1:1; `NSRegularExpression` is ICU-based (same class as JS regex) — behavior differences must be caught by vector tests, not assumed away.

## 4. Trust parity (23 rules, exact order, first-match-wins)

Port the full table from audit §3.2: no-playable-source → addon-placeholder-banner → addon-status-card → suspicious-extension → trailer-or-extra → addon-uncached-emoji → size-stub (<5MiB) → movie floors → new-release-virus/stub → series-result-for-movie → cinema-bare-untagged → title-mismatch → cinema-year-mismatch → filename-missing-sequel → fresh-cinema-fake-{bluray,4k-web,hdtv} → episode floors → series title-mismatch → season/episode-mismatch → scam-score≥5.

Include: cinema window (−90..+60 days), older-catalog (>730d or year gap>2), size floors (movie/episode/anime tables — exact MiB values in audit §3.3), title_matches (sequel markers, year tolerance 1–4, NFKD tokenization, stopwords, overlap≥2 or ratio≥0.5), short-format exemption, anime gate skips (rules 11,12,13,20,21,22), `strict=true` default.

## 5. Scoring parity (exact deltas)

Port every delta from audit §4.1–4.4 with exact numbers: cached +60, easynews +60, direct-url +25, resolution +25/20/8/2, DV +6, HDR +5, HEVC/AV1 +1, Atmos +3, TrueHD/DTS-HD MA +2, DD+ +1, ≥6ch +2, seeders min(⌊n/10⌋,10), trusted group +2, prev-episode-group +8, REMUX +3, PROPER/REPACK ≤+2, preferred-language +12, multi-language +4, prelinked-url +4, **origin-addon +250**, strong-addon +8, trusted-addon +4, addon-priority max(0,12−4p), fresh-theater bonuses +95/+75/+65/+25.

Negatives: zero-seeders −20/−8, year off-by-1 −75/−18, year mismatch −150/−70, CAM −80, TS/HDTS −60, TC −50, SCR −40, language −3/−14/−18/−12, scam −1..−8, bitrate budget −45/−120/−12 (soft +10 when cached), low-bandwidth −30/−60/−20/−45, size-mismatch −120/−60/−20 (YTS/YIFY exempt), cam-in-filename −200/−100, undersized 4K/1080p/720p −250/−200/−80, new-release −250/−200, fresh-fake family −200..−10, playability (DTS −6, TrueHD −4, mkv combo −3, avi/wmv −8, AV1 −2).

Corpus: isTracked = cached | url | seeders≥30; fractions; theater-dominated definition (tracked≥4, theater≥0.4, theater>webish). Tiers: ROUGH < SD < 720p < 1080p < 1080p_HDR < 4K < 4K_HDR < 4K_DV.

## 6. Ranking parity (Rust semantics — the shipped desktop behavior)

1. respectAddonOrder pre-sort (priority → returnIdx → score), else Rust's no-pre-sort.
2. Stable cached-first sort (Rust: any `url` OR active-debrid cached counts).
3. byTier = first cached per tier.
4. primary = highest-scored cached **non-theater** stream; fallback first non-theater; fallback first overall.
5. No preferAac.

## 7. Resolve & preflight parity

Port `resolve.ts` order: forceP2p → url (HEAD-probe web pages, DirectLink) → `#` = config-required → externalUrl → ytId → nzbUrl → infoHash (debrids sorted cached-first; uncached+not-committed gate) → p2p last. `validateLink`: size ≥80MiB / ≥40% expected; HEAD content-length 5s timeout. Preflight: Range 0-1 probe ×3, 1s delay, 2.5s timeout; 404/410 or <5MiB = stub; memoized per URL.

## 8. Test anchors (already live)

- `rust/harbor-core`: **56/56 green on Windows** (2026-09-02, cargo 1.98 GNU toolchain).
- Exact expected scores documented (e.g. 4K+HDR10+HEVC+Atmos 8ch = 36.0; cached rd MediaFusion = 88.0; CAM 720p = −72.0; CAM-only pool primary falls back to non-theater 1080p).
- 17 addon cache-flag fixtures (Comet/Torrentio/MediaFusion/AIOStreams/StreamFusion/Easynews) with expected cached/uncached slugs.

## 9. Maintained divergences (must be listed here)

| Divergence | Why |
|---|---|
| Torrent engine paths (forceP2p, p2p fallback) | BLOCKED on iOS (see platform gap) — resolve returns debrid/url paths only |
| Transcode/proxy rescue steps | desktop-only (platform gap) |
