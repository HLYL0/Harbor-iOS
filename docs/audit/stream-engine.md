# Harbor Stream Engine — Forensic Audit Report

**Scope:** Complete behavioral audit of Harbor's stream engine: parse → trust → score → rank (+ resolve).
**Sources audited (exact files):**

| Layer | Files |
|---|---|
| Rust canonical core | `harbor-core/src/lib.rs` (197 L), `harbor-core/src/parser.rs` (1779 L), `harbor-core/src/trust.rs` (1020 L), `harbor-core/src/scoring.rs` (1870 L), `harbor-core/src/types.rs` (361 L) |
| Tauri bridge | `src-tauri/src/streams.rs` (52 L) |
| TypeScript shell | `src/lib/streams/pipeline.ts`, `preflight.ts`, `resolve.ts`, `trust.ts`, `types.ts`, `parser.ts`, `parser/*.ts` (12 files), `scoring.ts`, `scoring/*.ts` (10 files), `anitomy.ts`, `episode-file.ts`, `episode-pipeline-input.ts`, `cached.ts`, `custom-filters.ts`, `addon-detect.ts`, `stream-ids.ts` |
| Test vectors | Rust `#[cfg(test)]` modules inside the 3 core files (56 tests total); TS fixtures `src/lib/streams/__fixtures__/addon-samples.ts` + `verify.ts` (17 samples) |

All line numbers below were verified by direct file reads on 2026-09-02.

---

## 1. Pipeline stages in exact execution order

### 1.1 Main pipeline — `runPipeline()` — `src/lib/streams/pipeline.ts:81`

| # | Stage | Function / file:line | Notes |
|---|---|---|---|
| 1 | Parallel fetch | `fetchLibraryStreams()` / `fetchAddonStreams()` — `pipeline.ts:113-121` | Library streams (debrid library) and addon streams fetched concurrently via `Promise.allSettled`; `presetStreams` (embedded meta streams) skip the addon fetch if non-empty. `fetchAddonStreams` receives `emitPartial` for progressive results. |
| 2 | Progressive partial results | `emitPartial` → `buildPartial` — `pipeline.ts:89-110` | Throttled to ≥250 ms between emissions (`lastPartialAt`). `buildPartial` runs the full local pipeline: merge → parse → trust → corpus → score → rank → rescue. |
| 3 | Merge + dedupe | `mergeAndDedupe()` — `pipeline.ts:237-262`; key builder `streamKey()` — `pipeline.ts:264-268` | Key priority: `hash:<infoHash lowercase>:<fileIdx>` → `url:<url>` → `n:<name>:<title>`. Duplicates merge `contributors` and `sources`; a later stream fills a missing `url` only. |
| 4 | Parse | `parseStream()` — TS `parser/parser-stream.ts:28` (see §2) | **Parsing always runs in TS** (parse-torrent-title based). The Rust core is NOT used for parsing in the main pipeline. |
| 5 | Anime enhancement | `enhanceAnimeStreams()` — `anitomy.ts:15` — called at `pipeline.ts:128-130` | Only when `input.isAnime`. Mutates parsedTitle/episode/episodeTitle/season/year/releaseGroup/resolution/animeHash/seasonPack. |
| 6 | Live debrid cache resolution | `pipeline.ts:140-180` | Collects unique infoHashes; runs `d.cacheCheck(hashes)` and `d.listLibrary()` for every debrid store; sets `p.cached[slug] = true` on hash hit, and `p.cached[slug] = true` + `p.inLibrary[slug] = true` for library hits. |
| 7 | Native core (Tauri only) | `runCorePipeline()` — `pipeline.ts:216-235` → Tauri command `streams_run_pipeline` — `src-tauri/src/streams.rs:15-38` | Rust path: `trust::apply_trust` → `scoring::compute_corpus_stats` → `scoring::score_stream` per stream → `scoring::rank_and_pick`, run in `tokio::task::spawn_blocking`. Returns `{ picker, rejected }`. On any error, or when not under Tauri, falls back to JS path (stage 8). |
| 8 | JS fallback (browser / core failure) | `applyTrust()` (`trust.ts:62`) → `computeCorpusStats()` (`scoring/scoring-corpus.ts:4`) → `scoreStream()` (`scoring/scoring-stream.ts:17`) → `rankAndPick()` (`scoring/scoring-rank.ts:4`) — `pipeline.ts:196-213` | Mirrors the Rust sequence. `rankAndPick` gets `PREFER_AAC` (`pipeline.ts:12` = `typeof window !== "undefined" && !("__TAURI_INTERNALS__" in window)`) — i.e. browser builds prefer AAC tracks. |
| 9 | Early-leak rescue | `finalizeWithRescue()` — `pipeline.ts:48-62`; `rescueCorroboratedLeaks()` — `pipeline.ts:17-46` | Re-admits trust-rejected streams, then re-runs corpus → score → rank on the union. |
| 10 | Return | `PipelineResult { picker, rejected, raw }` — `pipeline.ts:193-213` | |

### 1.2 Rust one-shot WASM pipeline — `run_pipeline_pure_js()` — `harbor-core/src/lib.rs:105-137`
`parse_stream` (per stream) → `trust::apply_trust` → `scoring::compute_corpus_stats` → `scoring::score_stream` (per kept stream) → `scoring::rank_and_pick(scored, active_debrids, respect_addon_order)`.
Differences vs the TS main pipeline: parsing IS done by Rust here; no anime enhancement; no live debrid cacheCheck; no rescue; no `preferAac`.

### 1.3 Playback resolution (post-rank) — `resolveStream()` — `src/lib/streams/resolve.ts:47-147`
Order: (a) `forceP2p` → local torrent engine; (b) `url` (≠ `"#"`) — HEAD-probe web pages, build `DirectLink`, `validateLink`; (c) `url === "#"` → `addon-not-configured`; (d) `externalUrl` → `external-url-only`; (e) `ytId` → `youtube-only`; (f) `nzbUrl` → `nzb-needs-external-player`; (g) `infoHash` with no debrids → p2p engine; (h) debrids sorted by cached-first (`sortDebridsForStream` — `resolve.ts:198-204`), each `playableUrl` → `validateLink`; uncached + not `userCommitted` → `uncached-not-committed`; last resort p2p engine.
`validateLink()` (`resolve.ts:149-196`): rejects `filesize < 80 MiB` (when expected size absent or > 80 MiB), rejects `< 40%` of expected size when expected > 100 MiB; HEAD `content-length` checks with 5 s timeout.

### 1.4 Link preflight probe — `preflightCheck()` — `src/lib/streams/preflight.ts:22-34`
`probe()` (`preflight.ts:63-103`): GET with `Range: bytes=0-1`; 3 attempts (`PROBE_ATTEMPTS = 3`), 1 s retry delay, 2.5 s per-attempt timeout (`PREFLIGHT_TIMEOUT_MS = 2500`); 404/410 → `stub`; total size < 5 MiB (`MIN_REAL_SIZE_BYTES = 5 * 1024 * 1024`) → `stub`; ≥ 5 MiB → ok. Memoized per URL (`memo` + `inflight` maps, `readPreflightMemo()` at `preflight.ts:18-20`).
## 2. Parser signals — every extracted field with exact rules

Entry points: Rust `parse_stream()` — `harbor-core/src/parser.rs:769-890`; TS `parseStream()` — `src/lib/streams/parser/parser-stream.ts:28-95`. The TS version delegates title/season/episode/etc. to the **`parse-torrent-title` npm library**; the Rust version re-implements the same contract in `ptt_parse()` — `parser.rs:463-750`. Divergences between the two are flagged **[TS≠RUST]**.

### 2.1 Text assembly
- `extract_filename_line()` — `parser.rs:1127-1184` / TS `parser-filename.ts:5-25`: splits title/`behaviorHints.filename`(or `fileName`)/description/name on newlines, strips Torrentio noise prefixes/suffixes (emoji set 👤👥💾📦⚡🌐📺🎬🔊 + whitespace — Rust `parser.rs:157-163`; TS superset adds 📅⚙️🔗📂🧑💻🇬🇧🇺🇸🌍🕵️♂️🔑 — `parser-filename.ts:3` **[TS≠RUST]**), then picks the line with the highest `filename_score()`.
- `filename_score()` — `parser.rs:1186-1253` / `parser-filename.ts:27-56`:
  - Rejections: `< 8 chars` → −100; starts with addon name (`torrentio|comet|mediafusion|aiostreams|knightcrawler|jackettio|torbox`) → −100; line is exactly a quality token (`4k|1080p|720p|480p|sd|hd|hdr|dv|uhd`) → −100; starts with noise emoji → −100; starts with `size|seeders?|peers?|languages?[:=]` → −50; starts with `[RD+|TB+|AD+|PM+|DL+] <word> library` → −50; zero technical markers → −20.
  - Scoring: len ≥ 20 → +2; ≥ 3 dots → +3; year `\b(?:19|20)\d{2}\b` → +2; resolution `\b\d{3,4}p\b` or `4k|uhd|2160p` → +2; episode `\bS\d{1,2}E\d{1,3}\b` → +3; source → +3; codec → +1; container `.mkv|mp4|m4v|avi|ts` → +2.
- Parse input: **filename line if found, else full joined text** (`parser.rs:791-796`); all field detections (HDR, source, audio, languages, size, seeders, cache flags…) run on the **full text** = `filenameLine + title + description + name` joined with spaces (`parser.rs:770-790`).

### 2.2 Title / year / season / episode / group (ptt_parse) — `parser.rs:463-750`
Rust-native regexes (parse-torrent-title does the equivalent in TS):
- **Year**: `[^a-zA-Z0-9][\([]?((?:19[0-9]|20[012])[0-9])[\)\]]?` (first capture; also moves `end_of_title` marker) — `parser.rs:477-487`.
- **Resolution raw**: `([0-9]{3,4}[pi])` → else `\b(4k)` → else `FHD|\b1080\b` → `"1080p"` → else `UHD` → `"4k"` — `parser.rs:489-516`.
- **Extended**: `EXTENDED(?:[\s.]CUT)?` (`:518-523`); **Theatrical**: `Theatrical(?:[. ]Cut)?` (`:525-530`); **Uncut**: `.+\bUNCUT\b` (`:532-536`); **OpenMatte**: `OPEN[. ]MATTE` (`:538-543`); **Hardcoded**: `HC|HARDCODED` (`:545-550`); **Proper**: `\b(?:REAL.)?PROPER\b` (`:552-557`); **Repack/Rerip**: `REPACK|RERIP` (`:559-564`); **Remastered**: `\bRemaster(?:ed)?\b` (`:566-571`); **Unrated**: `\bunrated|uncensored\b` (`:573-578`); **Criterion**: `\bCriterion\b` (`:580-585`).
- **Codec raw**: `h[-. ]?265|hevc` → `"h265"`; else `h[-. ]?264|avc` → `"h264"`; else `dvix|mpeg2|divx|xvid|x[-. ]?26[45]` (cleanup strips space/dot/dash) — `parser.rs:587-605`.
- **Channels**: `\d+[.\s](?:1|0)\b` (numeric like `5.1`) → else `2ch`→2.0, `6ch`→5.1, `8ch`→7.1 — `parser.rs:607-630`.
- **Bitdepth**: `\b(8|10|12|16|24)[-\s.]?bits?\b` — `parser.rs:632-641` (note: main-text BIT_DEPTH_RX only accepts 8|10|12, `parser.rs:340-341`).
- **Group**: `-[ \(\[]*(?:\w+[ \]\)]+)?(\w+(?:\.\w+)?)[\)\]]?(?:\.(?:mkv|mp4))?$` — `parser.rs:643-656`.
- **Season** (first match wins): `([0-9]{1,2})xall` → `S([0-9]{1,2}) ?E[0-9]{1,2}` → `([0-9]{1,2})x[0-9]{1,2}` → `(?:Saison|Season)[. _-]?([0-9]{1,2})` → `\bS([0-9]{1,2})([0-9])?` (only when group 2 absent, i.e. bare `S\d\d` without a following digit) — `parser.rs:658-707`.
- **Episode** (first match wins): `S[0-9]{1,2} ?E([0-9]{1,5})` → `[0-9]{1,2}x([0-9]{1,5})` → `[eé]p(?:isode)?[. _-]?([0-9]{1,5})` — `parser.rs:709-737`.
- **clean_title** — `parser.rs:752-767`: trims leading/trailing dots; if no spaces but dots exist → dots become spaces; `_` → space; trims trailing `(`/`_`; strips `"- "` suffix.

### 2.3 Resolution — `map_resolution()` — `parser.rs:900-916` / `parser-resolution.ts:3-11`
`contains("2160") || == "4k" || == "uhd"` → **4K/UHD**; `contains("1080")` → **1080p**; `contains("720")` → **720p**; `contains("480")` → **480p**; else **SD**.

### 2.4 HDR — `detect_hdr()` — `parser.rs:918-925` / `parser-hdr.ts:11-16` — ordered list, first match wins:
1. `\bDV[+\-\s.]?HDR10\+?\b|\bDoVi[+\-\s.]?HDR10\+?\b|\bDolby[\.\s]?Vision[+\-\s.]?HDR10\+?\b` → **DV+HDR10**
2. `\bDV\b|\bDoVi\b|\bDolby[\.\s]?Vision\b` → **DV**
3. `\bHDR10\+\b` → **HDR10+**
4. `\bHLG\b` → **HLG**
5. `\bHDR10?\b|\bHDR\b` → **HDR10**

### 2.5 Codec — `map_codec()` — `parser.rs:927-945` / `parser-codec.ts:3-11`
`contains("265") || == "hevc"` → HEVC; `contains("264") || == "avc"` → AVC; `contains("av1")` → AV1; `contains("vp9")` → VP9; `contains("mpeg")` → MPEG2; else Other.

### 2.6 Source — `detect_source()` — `parser.rs:947-954` / `parser-source.ts:20-25` — ordered list:
| # | Regex | Result |
|---|---|---|
| 1 | `\bHC[\s._\-]?(?:HDRip|HD[\s._\-]?Rip|CAM(?:Rip)?)\b` | CAM |
| 2 | `\b(?:HD|Clean|New|HQ|TS)[\s._\-]?CAM(?:Rip)?\b|\bCAM(?:Rip)?\b` | CAM |
| 3 | `\bHD[\s._\-]?TS\b|\bHDTS\b` | HDTS |
| 4 | `\bTELESYNC\b|\bTS[\s._\-]?Rip\b|\bPDVDRip\b` **[TS adds: `\bTS\b(?=[\s._\-]\d{3,4}[pi]\b)|(?<=\b(?:19|20)\d{2}[\s._\-])TS\b`]** | TS |
| 5 | `\bTELECINE\b|\bHD[\s._\-]?TC\b` **[TS adds: `\bTC\b(?=[\s._\-]\d{3,4}[pi]\b)|(?<=\b(?:19|20)\d{2}[\s._\-])TC\b`]** | TC |
| 6 | `\bSCREENER\b|\bDVDSCR\b|\bDVDScreener\b|\bBDSCR\b|\bWEB[\s._\-]?SCR\b|\bSCR\b` | SCR |
| 7 | `\bRemux\b` | REMUX |
| 8 | `\bBluRay\b|\bBDRip\b|\bBRRip\b` | BluRay |
| 9 | `\bWEB[\.\-]?DL\b` | WEB-DL |
| 10 | `\bWEBRip\b|\bWEB-Rip\b` | WEBRip |
| 11 | `\bHDRip\b` | HDRip |
| 12 | `\bDVDRip\b` | DVDRip |
| 13 | `\bHDTV\b` | HDTV |
| 14 | **TS only:** `\bWEB\b` → WEB-DL **[TS≠RUST]** | WEB-DL |

### 2.7 Audio codec — `parse_audio()` — `parser.rs:956-982` / `parser-audio.ts:19-32` — first match wins:
`\bAtmos\b`→Atmos; `\bTrueHD\b`→TrueHD; `\bDTS-HD\.?MA\b|\bDTS\.?HD\.?MA\b`→DTS-HD MA; `\bDTS\b`→DTS; `\bDDP?5?\.?1\+?\b|\bE-?AC3\b|\bDD\+\b`→DD+; `\bAC3\b`→AC3; `\bAAC\b`→AAC; `\bFLAC\b`→FLAC; `\bOpus\b`→Opus; else Other.

### 2.8 Channels & bit depth — `parser.rs:964-981`
- Channels: text regex `\b(7\.1|5\.1|6\.1|2\.1|2\.0)\b` (`:338-339`), mapped `7.1→8, 6.1→7, 5.1→6, 2.1→3, else 2` (`map_channels()` `:1000-1008`); fallback to ptt channels via `format_channels()` (`:984-998`); else **2**.
- Bit depth: `\b(8|10|12)\s*bit\b` → number, else ptt bitdepth.

### 2.9 Audio languages — `parse_languages()` — `parser.rs:1010-1068` / `parser-language.ts:153-180`
Three detectors, deduped in order:
1. **Word tokens** (`LANG_RX` `parser.rs:141-145`): ~60 token→language mappings (`LANG_TOKENS` `parser.rs:24-61`); `MULTI`/`DUAL` → "Multi". **[TS≠RUST]:** TS maps `LAT`/`LATINO`/`LATAM` → "Spanish (Latin America)" and adds `LATAM` to the regex (`parser-language.ts:13-15,82`); Rust maps them to plain "Spanish" and has no LATAM.
2. **Flag emoji** (`FLAG_RX` `parser.rs:147-149`, regional-indicator pairs → ISO code → `FLAG_TO_LANGUAGE` `parser.rs:63-102`; ~70 codes).
3. **ISO-639-1 pairs** (`ISO_PAIR_RX` `parser.rs:151-155`, ~50 codes → `ISO_PAIR_TO_LANGUAGE` `parser.rs:104-139`).
Composition: >1 concrete language → `["Multi", ...concrete]`; exactly 1 → `[concrete]`; 0 but "Multi" seen → `["Multi"]`; else `[]`.

### 2.10 Size, seeders, container
- **Size**: `behaviorHints.videoSize` wins if > 0 (`parser.rs:804-809`); else `(\d+(?:\.\d+)?)\s*(GB|MB|TB|GiB|MiB|TiB)\b` → binary multiples (TB/TiB ×1024⁴, GB/GiB ×1024³, MB/MiB ×1024²) rounded — `parse_size()` `parser.rs:1255-1274` / `parser-metadata.ts:44-54`.
- **Seeders**: `(?:👥|👤|S:|seeds?:?|\bS\s*=\s*)\s*(\d+)` — `parser.rs:171-173, 1276-1279`.
- **Container**: search order `behaviorHints.filename` → filename line → full text; regex `\.(mkv|mp4|m4v|avi|webm|mov|ts|wmv)\b` — `parser.rs:165-166, 1100-1125`.

### 2.11 Edition, year range, disc, repack, proper, hardcoded, remux
- **Edition** (`parse_edition()` `parser.rs:1523-1550`): ptt priority EXTENDED → UNRATED → THEATRICAL → UNCUT → REMASTERED → CRITERION → OPEN MATTE; else text regex `\b(IMAX|EXTENDED|DIRECTORS?[.\s]?CUT|THEATRICAL|UNRATED|UNCUT|REMASTERED|RESTORATION|CRITERION|OPEN[.\s]?MATTE|HYBRID)\b`, dots/spaces normalized to spaces.
- **Year range**: `\b(19\d\d|20\d\d)[\-\.](19\d\d|20\d\d)\b` with `0 < diff < 30` — `parser.rs:347-348, 1552-1562`.
- **Disc index**: `\bDISC\s*(\d+)\b` — `parser.rs:349, 1589-1592`.
- **Repack iteration**: `\bREPACK(\d+)?\b`; digit → n, bare → 1; else ptt.repack → 1, else 0 — `parser.rs:342-343, 1594-1606`.
- **Proper**: ptt proper (`parser.rs:845`).
- **Hardcoded**: `\b(HC|HARDCODED|HARDSUB)\b` on text OR ptt.hardcoded — `parser.rs:345-346, 846`.
- **Remux**: `\bRemux\b` on full text — `parser.rs:344, 836`.

### 2.12 Episode title — `parse_episode_title()` — `parser.rs:1070-1098` / `parser-metadata.ts:17-29`
Find `S{ss}E{ee}` (zero-padded) in filename; take suffix; strip leading `[.\-_\s]+`; cut at first `QUALITY_STOP_RX` match (`.` + 70+ quality tokens, `parser.rs:356-360`); dots/underscores→spaces, collapse whitespace; reject if length <2 or >80 chars or matches `^(?:e\d+|episode|hdtv|webrip)$`.

### 2.13 Season pack — `parse_season_pack()` — `parser.rs:1564-1587` / `parser-metadata.ts:83-88`
Only when ptt has season AND no episode. Rust: iterate `\b(complete|season[\s\.]?pack|s\d{1,2})\b` — true if `complete`, `season`, `season.`, `season `, or a bare `S\d\d` not followed by `E`. TS: single regex `\b(complete|season[\s\.]?pack|s\d{1,2}\b(?!e))\b`. **[TS≠RUST]** (different negative-lookahead semantics).

### 2.14 Release group & normalization; trusted groups
- `release_group_normalized` = uppercase group with `[^A-Z0-9]` removed (`parser.rs:832-835`, `GROUP_NORMALIZE_RX` `:407`).
- **Trusted groups** (51 entries, identical in Rust `parser.rs:8-22`, `scoring.rs:27-36`, and TS `parser-trusted-groups.ts:1-52`): FRDS, FRAMESTOR, FORM, EVO, RARBG, ETHEL, FLUX, QXR, MEGUSTA, ION10, PSA, AMIABLE, GALAXYRG, WEBDV, RZEROX, SIC, TGX, NTB, NTG, TEPES, GECKOS, SUCCESSFULCRAB, SUBSPLEASE, ERAI, ERAIRAWS, JUDAS, ASW, EMBER, ANE, CLEO, BEATRICERAWS, AKIHITO, VODES, NANDESUKA, SMOL, TENRAISENSEI, GST, ANIMEKAIZOKU, REINFORCE, RAWS, OZR, PURGATORY, SHK, KOTUWA, KIRION, COMMIE, DAMEDESUYO, MTBB, GJM, SOFCJ.
- `is_trusted_group()` — `parser.rs:896-898`.

### 2.15 Anime CRC hash — `parse_anime_hash()` — `parser.rs:1608-1611`
`(?i)\[([0-9A-F]{8})\]` → uppercased 8-hex-char CRC32-style checksum (e.g. `[AB12CD34]`).

### 2.16 Scam score — `compute_scam_score()` — `parser.rs:1613-1650`
| Condition | +points |
|---|---|
| resolution 4K and size < 5 GiB | +3 |
| 1080p and size < 700 MiB | +3 |
| 720p and size < 250 MiB | +3 |
| SD and size < 250 MiB | +3 |
| SD and source == Other | +2 |
Max 8 (4K+SD branches are mutually exclusive; SD caps at 5).

### 2.17 Debrid cache flags — `parse_cache_flags()` — `parser.rs:1286-1416` / `parser-cache-flags.ts:51-154`
Runs on invisibles-stripped text (`INVISIBLE_RX` removes U+200B-U+200D/U+2060/U+FEFF, `VARIATION_SELECTOR_RX` removes U+FE0F — `parser.rs:409-413, 1281-1284`). Two-phase: **uncached (deny) first, cached second (denied slugs can't be set cached)**.
Phase 1 — mark uncached:
- `[RD|TB|AD|PM|DL](?:[\s\-]?download|⬇️?|⏳)]` per slug — `parser.rs:184-198`
- Jackettio bare bracket: `\[(RD|TB|AD|PM|DL|OC|ED|Putio)\]\s+(?:Jackettio|jackettio)\b` — `:200-202`
- StreamFusion `^⬇️?download\n([^\n]+)` service line — `:208-210`
- Generic `(?:⏳|⬇️?|🔻|❌)\s*(need cache|download via|not ready|uncached on)?\s*<service>` — `:244-248`
- Template addons (AIOStreams Prism `❌ Not Ready`, GDrive `🎟️`, MediaFusion `\b(SVC)\s*[⏳⬇🔻❌]`) → slug from bingeGroup (`comet|<svc>|…` `parser.rs:415-416,1497-1508`) → MediaFusion abbrev (`:1418-1450`) → addon name slug (`:1464-1491`) — `parser.rs:1333-1344`. **[TS≠RUST]:** TS additionally triggers on AIOStreams generic `☁|UNCACHED` when addon is aiostreams (`parser-cache-flags.ts:22-23,85-97`).
Phase 2 — mark cached:
- `[RD+⚡]` etc. per slug — `parser.rs:178-182, 1352-1366`
- StreamFusion `^⚡instant\n([^\n]+)` — `:204-207, 1368-1376`
- Generic `(?:⚡️?|✅)\s*(cached on|instant on|ready on)?\s*<service>` — `:239-243, 1378-1384`
- Templates: AIOStreams `(Instant\b)` / `⚡ Ready` / `🎫`, StreamFusion `^⚡instant`, MediaFusion `\b(SVC)\s*[+⚡✅]` — `:212-218, 224-230, 1386-1401`. **[TS≠RUST]:** TS adds AIOStreams generic `[🚀🌩📫]|\bcached\b` (`parser-cache-flags.ts:22,117-123`).
- HTTP-URL heuristic: url starts `http(s)://` and (contains a debrid hostname OR addon name matches `mediafusion|comet|torrentio|aiostreams|knightcrawler|jackettio|streamfusion|easynews`) → set addon-name slug cached — `parser.rs:418-424, 1403-1413`.
- **[TS-only]** ElfHosted rule: url or addon name matches `elfhosted` and text matches `\belf[\s\-_]?cache\b|cached\s+on\s+elfhosted` → mark rd/tb/ad/pm/dl (or binge-group slug) cached — `parser-cache-flags.ts:31,143-151`. **Missing in Rust.**

MediaFusion service regex list: `RD|TB|TRB|AD|PM|DL|OC|ED|ST|DBD|DB|PKP|PP|SDR|SAB|NZB|DAV|EN|NNTP|QB-WD|Putio|Offcloud|EasyDebrid` (`parser.rs:222`).
## 3. Trust gate — every rule with exact conditions

Entry points: Rust `apply_trust()` — `harbor-core/src/trust.rs:138-158`, per-stream `check_one()` — `trust.rs:160-399`; TS `applyTrust()` — `src/lib/streams/trust.ts:62-80`, `checkOne()` — `trust.ts:102-269`. The two are line-for-line equivalent except where flagged. Rules are checked **in the order listed; the first match wins** (one rejection per stream).

### 3.1 Gate preconditions
- `opts.disabled` → everything passes (`trust.rs:139-144`; set from `episode-pipeline-input.ts:98` when user disables the filter, for addon-native meta, or when embedded streams exist).
- `strict` defaults **true** (`trust.rs:311-312`, `default_true()`; TS `opts.strict ?? true` — `trust.ts:73`).
- **Cinema window**: `is_in_cinema_window()` — `trust.rs:640-647`: release date must parse as ISO-8601 (via `parse_iso_date_to_unix_ms()` `:587-601`, civil-date algorithm `:603-611`) and satisfy `-90 < days_since_release < 60`.
- **Older catalog**: `is_older_catalog()` — `trust.rs:649-660`: release date > 730 days ago, OR `current_year - expected_year > 2`.
- `ANIME_JA_RX` (`trust.rs:107`) is defined but **never used** (dead code).

### 3.2 Rejection rules in order — `check_one()` — `trust.rs:160-399`

| # | Reason string | Exact condition | Location |
|---|---|---|---|
| 1 | `no-playable-source` | None of `url` / `infoHash` / `ytId` / `externalUrl` / `extra["nzbUrl"]` present | `trust.rs:167-174` |
| 2 | `addon-placeholder-banner` | `PLACEHOLDER_BANNER_RX` = `(?:🚫|⚠️?|❗|ℹ️?)\s*(?:no\s+streams?\s+(?:found|available)|streams?\s+filtered|streams?\s+blocked|filtered)` matches `title + name + description` | `trust.rs:176-184` (regex `:73-78`) |
| 3 | `addon-status-card` | `infoHash` absent AND url not a video extension (`\.(mkv|mp4|m4v|avi|webm|mov|ts)(\?|$)` `:87-88`) AND `STATUS_LINE_RX` (`\b(?:expires?\s+in|days?\s+left|premium\s+(?:active|expir(?:ed|ing))|api\s+limit|quota\s+used)\b` `:80-85`) matches AND behaviorHints has neither non-zero `videoSize` nor non-empty `filename` | `trust.rs:185-209` |
| 4 | `suspicious-extension:<ext>` | lowercased behaviorHints `filename` ends with one of `.exe .zip .rar .lnk .scr .bat .iso .img` | `trust.rs:211-220` (blacklist `:60-62`) |
| 5 | `trailer-or-extra` | `TRAILER_RX` = `(?:^|[^a-z0-9])(?:trailer|teaser|tlr|trl|tra(?:iler)?|sneak[\s.\-_]?peek|preview|behind[\s.\-_]?the[\s.\-_]?scenes|featurette|making[\s.\-_]?of|deleted[\s.\-_]?scene|bloopers?|gag[\s.\-_]?reel|extras?|promo)(?:$|[^a-z0-9])` matches `filename + title + name` (lowercased) | `trust.rs:222-224` (regex `:90-95`) |
| 6 | `addon-uncached-emoji` | `UNCACHED_EMOJI_RX` = `[⬇⏳⌛⏬🔽📥☁]` matches `title + name + description` | `trust.rs:226-228` (regex `:71`) |
| 7 | `size-stub` | parsed `size` present and `< 5 MiB` (`TINY_STUB_FLOOR` `:15`) | `trust.rs:230-234` |
| 8 | `movie-stub-too-small-for-{res}` | `kind == "movie"`, size present, size < movie floor (table below) | `trust.rs:239-249` |
| 9 | `new-release-virus-{sizeMB}mb` | `kind == "movie"` AND cinema window AND source NOT in {CAM, TS, HDTS, TC} AND size < 250 MiB | `trust.rs:251-259` |
| 10 | `new-release-stub-{sizeMB}mb` | same context, size < 500 MiB AND not short-format | `trust.rs:260-263` |
| 11 | `series-result-for-movie` | `kind == "movie"` AND NOT `isAnime` AND (`seasonPack` OR `season` OR `episode` present) | `trust.rs:266-269` |
| 12 | `cinema-bare-untagged` | `strict` AND `kind == "movie"` AND NOT `isAnime` AND cinema window AND `expectedYear` set AND `year == None` AND `source == Other` AND `resolution == SD` | `trust.rs:271-281` |
| 13 | `title-mismatch` | `strict` AND `kind == "movie"` AND `expectedTitle` set AND `parsedTitle` non-empty AND `!title_matches(...)` (see §3.3) | `trust.rs:283-296` |
| 14 | `cinema-year-mismatch:{s}-vs-{e}` | `strict` AND `kind == "movie"` AND cinema window AND `year != expectedYear` (both present) | `trust.rs:298-304` |
| 15 | `filename-missing-sequel` | `strict` AND `kind == "movie"` AND expected title has sequel marker ≥ 2 AND `filename + title` lacks the digit/roman/word token (see §3.4) | `trust.rs:306-318` |
| 16 | `fresh-cinema-fake-bluray` | `strict` AND `kind == "movie"` AND cinema window AND (`source == BluRay` OR `remux`) | `trust.rs:320-323` |
| 17 | `fresh-cinema-fake-4k-web` | same window AND `resolution == UHD` AND `source ∈ {WebDl, WEBRip, BDRip, HDRip}` | `trust.rs:324-331` |
| 18 | `fresh-cinema-fake-hdtv` | same window AND `source == HDTV` AND `resolution ∈ {UHD, P1080}` | `trust.rs:332-337` |
| 19 | `episode-stub-too-small-for-{res}` | `kind == "series"` AND size present AND not short-format AND size < episode floor (anime table if `isAnime`) | `trust.rs:339-355` |
| 20 | `title-mismatch` | `strict` AND `kind == "series"` AND NOT `isAnime` AND title check fails | `trust.rs:357-370` |
| 21 | `season-mismatch:{s}-vs-{e}` | `strict` AND NOT `isAnime` AND no `fileIdx` AND NOT `seasonPack` AND both seasons present AND unequal | `trust.rs:374-382` |
| 22 | `episode-mismatch:{s}-vs-{e}` | same gate, episodes unequal | `trust.rs:384-392` |
| 23 | `scam-score-{n}` | `scamScore >= 5` AND NOT `allowCam` AND NOT older catalog | `trust.rs:394-396` |

Short-format exemption (`is_short_format()` — `trust.rs:408-417`): `\b(short|shorts|mini|mini[\s.\-_]?episode|ova|special|specials|skit|sketch|chibi|micro|webisode|vignette|interlude)\b` on `filename + title + name` skips rules 10 and 19.

### 3.3 Size floors (MiB, binary) — `trust.rs:17-48` / `trust.ts:37-59`

**Movie floors** — tuple order: `(cinema-window, normal, older-catalog)`:
| Resolution | cinema | normal | older |
|---|---|---|---|
| 4K | 2560 | 1536 | 600 |
| 1080p | ⌈6 GiB/5⌉ = 1288.49 | 700 | 250 |
| 720p | 600 | 400 | 120 |
| 480p | 250 | 150 | 50 |
| SD | 200 | 100 | 25 |

**Episode floors**: 4K 1024/600/200 · 1080p 400/250/100 · 720p 200/120/40 · 480p 80/50/12 · SD 50/30/8.
**Anime episode floors**: 4K 600/400/150 · 1080p 220/150/50 · 720p 100/60/20 · 480p 40/28/8 · SD 25/18/5.
(Rust `movie_min_size` uses `(GIB*6).div_ceil(5)` for the 1080p cinema value = 1,288,490,189 B; TS uses `Math.round(1.2 * GIB)` = the same. 4K episode value: Rust 1024 MiB = TS `Math.round(1.0*GIB)` = 1,073,741,824 B. Parity verified.)

### 3.4 Title matching — `title_matches()` — `trust.rs:494-548` / `trust.ts:339-374`
1. **Sequel markers** (`sequel_marker()` `trust.rs:464-478`): strip `\(\d{4}\)` and `\b(part|chapter|vol|volume)\b`; trailing token `(\d{1,2}|[ivx]+)` → 2-20 for digits, else roman `ii..x` map (`trust.rs:118-131`). Expected-has-sequel ≠ parsed-has-sequel → reject; expected-has-sequel + parsed-none → require `|parsedYear − expectedYear| ≤ tolerance`; expected-none + parsed-seq ≥ 2 → same year check.
2. **Year tolerance** (`year_tolerance_for()` `trust.rs:480-492`): age = currentYear − expectedYear; ≥30 → 4; ≥15 → 3; ≥5 → 2; else 1.
3. **Tokenization** (`tokenize()` `trust.rs:570-585`): lowercase → NFKD normalize → strip U+0300-U+036F → words `[a-z0-9]+` → keep len ≥ 3 and not in TITLE_STOPWORDS (`trust.rs:109-116`).
4. **Overlap** (`count_overlap()` `trust.rs:550-568`): exact word OR prefix-overlap of words ≥ 4 chars.
5. **Short-title guard**: `expected_tokens ≤ 2 && parsed_tokens − overlap > 2` → reject (e.g. expected "Obsession" vs parsed "DBM Obsession Viva Las Vegas").
6. **Pass if** `expectedRatio ≥ 0.5 || parsedRatio ≥ 0.5 || overlap ≥ 2`.
## 4. Scoring weights and ranking — exact numbers

Entry points: Rust `score_stream()` — `harbor-core/src/scoring.rs:836-1233`; TS `scoreStream()` — `src/lib/streams/scoring/scoring-stream.ts:17-253`. The two are numerically identical (verified against the Rust unit tests in `scoring.rs:1306-1870`). Each applied delta is recorded as a `ScoreReason { signal, delta }` and appended to `reasons` only when non-zero (Rust: `scoring.rs:869, 887-903, 906…`; TS: `if (delta)`).

### 4.1 Positive deltas (in application order within `score_stream`)
| Signal | Delta | Condition |
|---|---|---|
| `cached` | **+60** | any active-debrid slug is `cached[slug] === true` (or Easynews, below) |
| `easynews-direct` | **+60** | addon name OR parsed title matches `/easynews/i` (mutually exclusive with `cached`) |
| `direct url` | **+25** | not cached, `url` present |
| `4K` / `1080p` / `720p` / `480p` | **+25 / +20 / +8 / +2** | resolution (`resolution_points()` `scoring.rs:282-305`) |
| `DV+HDR10` / `DV` | **+6** | hdrFormat is DV or DV+HDR10 |
| `HDR10` / `HDR10+` / `HLG` | **+5** | any other hdrFormat |
| `HEVC` / `AV1` | **+1** each | codec |
| `Atmos` | **+3** | audio codec |
| `TrueHD` / `DTS-HD MA` | **+2** | audio codec |
| `DD+` | **+1** | audio codec |
| `{n}.0 channels` | **+2** | `audio.channels >= 6` |
| `seeders={n}` | **+min(⌊n/10⌋, 10)** | not cached, seeders > 0 (0-9 seeders → +0) |
| `group:{name}` | **+2** | release group in the 51-entry trusted list |
| `prev-episode-group:{g}` | **+8** | `releaseGroupNormalized === scoreOpts.preferredReleaseGroup` |
| `REMUX` | **+3** | `remux` flag |
| `PROPER` / `REPACK{n}` | **+min(2, repackIteration ∥ 1)** | proper OR repackIteration > 0 (proper with iteration 0 → +1) |
| `preferred-language` | **+12** | any parsed language matches any preferred (case-insensitive, prefix allowed) |
| `multi-language` | **+4** | languages contain "Multi", no preferred match, NOT preferSingleAudioTrack |
| `prelinked-url` | **+4** | `url` present and not cached |
| `origin-addon` | **+250** | `addonId === scoreOpts.preferAddonId` (dominant signal) |
| `strong-addon` | **+8** | addon name matches `/mediafusion|comet/i` |
| `trusted-addon` | **+4** | addon name matches `/mediafusion|comet|easynews|torrentio/i` |
| `addon-priority-{p}` | **+max(0, 12 − 4p)** | addon priority p (p=0 → +12, p=1 → +8, p=2 → +4, p≥3 → 0) |
| `fresh-theater-cinema-window` | **+95 (CAM) / +75 (TS,HDTS) / +65 (TC)** | theater-dominated fresh window (§4.5) |
| `fresh-theater-mild-boost` | **+25** | theater capture, non-dominated, days < 14 |

### 4.2 Negative deltas
| Signal | Delta | Condition |
|---|---|---|
| `zero-seeders-stale-meta` | **−20** | not cached, no url, infoHash present, seeders == 0 |
| `zero-seeders-soft` | **−8** | infoHash present, seeders == 0, not cached (stacks with the above) |
| `year-off-by-1:{s}vs{e}[-recent]` | **−75 recent / −18 old** | parsed year differs by exactly 1; recent = release date within 365 days |
| `year-mismatch:{s}vs{e}[-recent]` | **−150 recent / −70 old** | difference ≥ 2 |
| `CAM penalty` | **−80** | source CAM |
| `Telesync penalty` | **−60** | source TS or HDTS |
| `Telecine penalty` | **−50** | source TC |
| `Screener penalty` | **−40** | source SCR |
| `language-unknown` | **−3** | preferred languages set, parsed list empty |
| `html5-multi-audio-penalty` | **−18** | Multi language, no preferred match, preferSingleAudioTrack |
| `language-mismatch` | **−14** | no preferred match, not Multi |
| `html5-multi-audio-penalty` | **−12** | no preferred languages set, preferSingleAudioTrack, Multi |
| `scam-penalty` | **−scamScore** | scamScore > 0 (1-8) |
| `webview2-unfriendly` | see §4.3 | playability (sums) |
| `bitrate-exceeds-budget:{r}>{b}Mbps` | **−45** (or **−120** if required > 1.5× budget); **+10 softer when cached** | required bitrate > 1.1× bandwidth budget |
| `bitrate-tight:{r}/{b}Mbps` | **−12** | required bitrate > 0.8× budget (but ≤ 1.1×) |
| `low-bandwidth-4k` | **−30 cached / −60 not** | 4K and budget < 25 Mbps |
| `low-bandwidth-1080p` | **−20 cached / −45 not** | 1080p and budget < 8 Mbps |
| `size-mismatch` | **−120 / −60 / −20** | size < runtime-derived minimum by ratio < 0.25 / < 0.5 / < 0.75 (exempt: theater sources, lossy groups YTS/YIFY/YTSAG/YTS-AG) |
| `title-says-hires-filename-says-cam` | **−200 (4K) / −100 (1080p)** | CAM marker regex in name/title/filename/desc while parsed source is not theater and resolution is 1080p/4K |
| `4k-undersized-{x}gb` | **−250** | movie, days < 90, non-theater, 4K and size < 6 GiB |
| `1080p-undersized-{x}gb` | **−200** | same, 1080p and size < 1.5 GiB |
| `720p-undersized-{x}gb` | **−80** | same, 720p and size < 0.6 GiB |
| `new-release-virus-{n}mb` | **−250** | movie, days < 90, non-theater, size < 250 MiB |
| `new-release-no-label-{n}mb` | **−200** | same, size < max(500 MiB, runtime×5 MiB/min) |
| `fresh-fake-remux` | **−200** | theater-dominated, remux/bluray claims |
| `fresh-fake-prerelease` | **−160** | theater-dominated, days < 0 |
| `fresh-fake-prebluray` | **−90** | theater-dominated, 0 ≤ days < 14 |
| `fresh-fake-soft` | **−45** | theater-dominated, days ≥ 14 |
| `fresh-prebluray-suspect` | **−55** | non-dominated, remux/bluray, days < 14 |
| `fresh-prerelease-soft` | **−35** | non-dominated, days < 0, no valid size |
| `fresh-soft-flag` | **−10** | non-dominated fallback |

### 4.3 Playability penalty — `playability_penalty()` — `scoring.rs:371-391`
DTS or DTS-HD MA −6; TrueHD −4; mkv container + (DTS or TrueHD) −3; avi/wmv container −8; AV1 codec −2. All stack (max −19, e.g. DTS in mkv: −9). Emitted as one reason `webview2-unfriendly`.

### 4.4 Runtime-derived minimums — `expected_min_size_bytes()` — `scoring.rs:457-469`
MB/min by resolution: 4K 60 · 1080p 18 · 720p 8 · 480p 3 · SD 2; × runtime × 1048576. Used for `size-mismatch` and `hasValidSize`.

### 4.5 Fresh theatrical adjust — `fresh_theatrical_adjust()` — `scoring.rs:703-834`
Preconditions: `mediaKind == "movie"`, release date parses, `days < 150` (`THEATER_WINDOW_DAYS` `:25`). Theater-dominated corpus = `trustedTrackedCount ≥ 4 && theaterCaptureFraction ≥ 0.4 && theaterCaptureFraction > webishFraction`. If not dominated and `days ≥ 30` (`SHORT_FRESH_DAYS` `:24`) → no-op. See table §4.1/§4.2 for the deltas. `is_theater_source()` = CAM/TS/HDTS/TC (`:58-60`); `is_webish_source()` = WEB-DL/WEBRip/BluRay/BDRip (`:62-64`).

### 4.6 Tier assignment — `tier_of()` — `scoring.rs:393-419` / `scoring-resolution.ts:11-26`
1. Source ∈ {CAM, TS, HDTS, TC, SCR} → **ROUGH**
2. 4K + (DV or DV+HDR10) → **4K_DV**; 4K + any HDR → **4K_HDR**; 4K → **4K**
3. 1080p + HDR → **1080p_HDR**; 1080p → **1080p**
4. 720p → **720p**
5. else → **SD**
Tier key order (`TIER_ORDER`, `scoring-types.ts:27`): `4K_DV > 4K_HDR > 4K > 1080p_HDR > 1080p > 720p > SD > ROUGH` (Rust encodes the same order via enum declaration, `types.rs:98-116`).

### 4.7 Ranking — `rank_and_pick()` — Rust `scoring.rs:1255-1304` vs TS `scoring-rank.ts:4-38` — ⚠ PARITY-CRITICAL DIFFERENCES
Both implementations:
1. Optional pre-sort by addon order (`respectAddonOrder`): `addonPriority` asc → `addonReturnIdx` asc → score desc (Rust `:1261-1271`; TS `:17-19`; missing values = `u32::MAX` / `Number.MAX_SAFE_INTEGER`).
2. Else pre-sort: score desc (TS `:18`); Rust skips the pre-sort in that branch and only does the cached-first stable sort.
3. **Stable cached-first sort** (both): cached = `url` present OR any active-debrid `cached[slug]` (TS additionally requires `!hasUncachedMarker(s)` for the url case — `scoring-rank.ts:10-11`; Rust counts any `url` — `scoring.rs:1248-1253`). ⚠ **Rust counts uncached-marker URLs as cached; TS does not.**
4. **byTier**: first stream per tier in cached-first order (both).
5. **primary**:
   - **Rust** (`scoring.rs:1284-1297`): if `respectAddonOrder` → first cached **non-theater** stream; else `max_by(score)` among cached non-theater; fallback first non-theater; fallback `first()` overall. ⚠ **Rust skips theater sources for primary.**
   - **TS** (`scoring-rank.ts:31-35`): `all.find(isCached)` (≡ highest-scored cached when sorted by score, or first addon-ordered cached); if `preferAac` → first cached with `audio.codec === "AAC"`. ⚠ **TS never skips theater for primary; preferAac exists only in TS** (passed from `pipeline.ts:59,95,211` as `PREFER_AAC`; the Rust signature has no such parameter — `scoring.rs:1255-1259`, called with 3 args at `src-tauri/src/streams.rs:30`).

### 4.8 Corpus statistics — `compute_corpus_stats()` — Rust `scoring.rs:198-242` / TS `scoring-corpus.ts:4-37`
`isTracked` = cached on active debrid OR `url` OR seeders ≥ 30 (`TRACKING_MIN_SEEDERS` `:23`). Outputs: `daysSinceRelease`, `trustedTrackedFraction` = tracked/total, `theaterCaptureFraction` = theater-tracked/tracked (÷1 if 0), `webishFraction`, `trustedTrackedCount`. Rust additionally computes `medianSize`, `p90Size`, `p10Seeders`, `p90Seeders` (nearest-rank percentile, `:244-260`) — exposed in the wasm/Js shape (`lib.rs:155-165`) but **not consumed by any scoring function in either implementation**.
## 5. Anime-specific handling

### 5.1 Pipeline wiring
- `isAnime` is derived in `buildEpisodePipelineInput()` — `episode-pipeline-input.ts:64`: `streamIds.some(id => id.startsWith("kitsu:") || id.startsWith("mal:"))`. It flows into both `trust.isAnime` (`:104`) and `input.isAnime` (`:88`), which triggers `enhanceAnimeStreams()` at `pipeline.ts:128-130`.
- `buildStreamIds()` — `stream-ids.ts:3-56`: for kitsu/mal/anilist/anidb metas, episode queries use `kitsuStreamId` (or `kitsu:<id>:<ep>`); IMDB `tt…:s:e` pairs are only added when the meta is NOT anime or when `episode === imdbEpisode` (`imdbEpAligned`); the trust expected season/episode fall back to the anime-numbering `episode.season`/`episode.episode` rather than the IMDB-mapped ones (`episode-pipeline-input.ts:65-68,83-84,95-96`).
- Trust gates that are **skipped for anime** (`isAnime`): `series-result-for-movie` (rule 11), `cinema-bare-untagged` (12), title-mismatch (13 & 20), season-mismatch (21), episode-mismatch (22); anime uses its own smaller size floors (rule 19).
- Trust `allowSeasonPacks` / `allowCam` / `allowSizeOutliers` are set to `!strictMode` (`episode-pipeline-input.ts:102-103`); note `allowSizeOutliers` and `requirePreferredLanguage`/`preferredAudioLangs` are **declared but never read** by trust/scoring logic in either language (dead options).

### 5.2 CRC / anime hash
- Main parser: `\[([0-9A-F]{8})\]` → `animeHash` (`parser.rs:175-176, 1608-1611`) — the classic anime CRC32-in-brackets marker.
- Anime enhancer re-extracts the same pattern from the filename and overwrites `s.animeHash` (`anitomy.ts:51, 73-77, 30`).

### 5.3 Anitomy-style enhancer — `enhanceAnimeStreams()` — `src/lib/streams/anitomy.ts:15-33`, `parseAnimeFilename()` `:60-135`
Per stream, parses the primary filename (behaviorHints.filename, else first title/description/name line containing a video extension — `anitomy.ts:35-48`):
- Leading `[Group]` → releaseGroup (normalized = uppercase alphanumerics, `:25-28, 67-71`).
- `\[([0-9A-Fa-f]{8})\]` → fileChecksum → animeHash (`:51,73-77`).
- Resolution `\b(2160p?|1080p?|720p?|480p?|4k)\b` (`:50,79-80`).
- Year `(?:^|[^\d])((?:19|20)\d{2})(?:[^\d]|$)` clamped 1900-2100 (`:54,82-86`).
- Season/episode `\b[Ss](\d{1,2})[\s._-]?[Ee](\d{1,4})\b`, else season-only `\b(?:Season|S)[\s._-]?(\d{1,2})\b` (`:52-53,88-95`).
- Episode number fallback (brackets/parens stripped first, `:97-101`): `\s-\s(\d{1,4})(?:v\d)?` or bare `(?:Ep?(?:isode)?[\s._-]?)?(\d{1,4})(?:v\d)?` before a `[`/`(`/end/separator (`:56,103-111`).
- Release group fallback: `-([A-Za-z0-9_]+)(?:\.[a-z0-9]{2,4})?$` when not all-digits (`:55,113-116`).
- **Batch detection**: `\b(?:BATCH|COMPLETE|SEASON\s*PACK)\b`, or numeric range `\b(\d{1,4})\s*[-~]\s*(\d{1,4})\b` with `hi − lo ≥ 2 && hi ≤ 999` → `isBatch` → `s.seasonPack = true` (`:57-58,118-129,31`).
- Title extraction: cut at ` - <ep>`, remove SxE/season/resolution/extension tokens, dots/underscores→spaces (`extractTitle()` `:137-150`). Episode title: text after ` - <ep> - `, cut at `[` (`extractEpisodeTitle()` `:152-162`).

### 5.4 Episode file matching — `src/lib/streams/episode-file.ts`
- `episodeFileRegex(season, episode)` — `:5-12`: `s0*{S}[^0-9]?e0*{E}(?!\d)` | zero-padded `{SS}{EE}` | `\b{S}x0*{E}(?!\d)` (case-insensitive).
- `matchEpisodeFileIndex(names, hint)` — `:14-25`: first name matching the regex that also ends with a video extension (`\.(mkv|mp4|avi|mov|m4v|webm|ts|flv|wmv|m2ts|mpg|mpeg|ogv|3gp)`), else the first regex match, else −1. Used by `resolve.ts` (`tryLocalEngine`/`selectEngineFileIdx` `:288-295`) when the stream has no `fileIdx`; fallback = largest file by length.

## 6. Debrid cache flags — consolidated

1. **Static (name-parsed) flags** — `parse_cache_flags()` `parser.rs:1286-1416` / `parser-cache-flags.ts:51-154`: full rules in §2.17. Slugs: `rd, tb, ad, pm, dl` (`types.rs:118-130`).
2. **Live (API) flags** — `pipeline.ts:140-180`: for every configured debrid store, `cacheCheck(hashes)` sets `cached[slug]=true` on hits; `listLibrary()` sets both `cached[slug]` and `inLibrary[slug]` — this runs after parsing and after anime enhancement, on the merged parsed list.
3. **Marker helpers** — `src/lib/streams/cached.ts`: `hasUncachedMarker()` `:4-11` = `\b(?:rd|ad|pm|dl|tb|oc)\s*download\b|\buncached\b|[⬇⏳⌛⏬🔽📥☁]`; `hasCachedMarker()` `:13-20` = `[⚡✅]`. `hasUncachedMarker` feeds TS ranking (`scoring-rank.ts:10-11`) and `resolve.ts` (P2P fallback eligibility when user committed, `:120-123`).
4. **Resolve-time gating** — `resolve.ts:108-123`: without `userCommitted`, a stream with no `cached[slug] === true` and no `inLibrary[slug] === true` among sorted debrids → `uncached-not-committed` (user must confirm the download).
5. **Custom filter** — `matchesCustomFilter()` `custom-filters.ts:130-134`: `cachedOnly` passes when any `cached` or `inLibrary` value is true.

## 7. Canonical test vectors with expected outputs

### 7.1 Rust unit tests (56 tests, exact expectations)
**Parser** (`harbor-core/src/parser.rs:1652-1779`, 8 tests):
| Test (file:line) | Input → expected |
|---|---|
| `parses_torrentio_1080p_webdl` (`:1667`) | `"The.Matrix.1999.1080p.WEB-DL.DDP5.1.H.264-FLUX\n👤 25 💾 2.5 GB ⚡ Real-Debrid"` (addon "Torrentio") → resolution P1080, codec AVC, source WEB-DL, year 1999, audio DD+ / 6 ch, group "FLUX" (norm "FLUX"), size > 2e9, seeders 25, cached.rd == true |
| `parses_yts_1080p_x265` (`:1688`) | `"The.Dark.Knight.2008.1080p.BluRay.x265-YTS"` → P1080, HEVC, BluRay, 2008 |
| `parses_cam_release_lowest_quality` (`:1701`) | `"Some.Movie.2024.HDCAM.x264-NEW\n💾 1.2 GB"` → source CAM, year 2024 |
| `parses_4k_dv_hdr10` (`:1712`) | `"Dune.Part.Two.2024.2160p.UHD.BluRay.REMUX.DV.HDR10.HEVC.TrueHD.7.1.Atmos-FraMeSToR\n💾 80.5 GB"` → UHD, HEVC, REMUX, DV+HDR10, remux, Atmos, 8 ch, 2024, group "FraMeSToR" (trusted) |
| `detects_season_pack` (`:1732`) | `"Breaking.Bad.S01.Complete.1080p.BluRay.x264-DEMAND"` → season 1, episode None, seasonPack true, P1080 |
| `detects_episode_with_title` (`:1745`) | `"The.Office.S03E10.A.Benihana.Christmas.720p.WEB-DL.x264.mkv"` → S3E10, P720, episodeTitle contains "benihana", container mkv |
| `empty_stream_falls_back_to_defaults` (`:1760`) | empty → SD / Other / Other |
| `behavior_hints_video_size_used` (`:1773`) | videoSize 5e9 → size 5_000_000_000 |

**Trust** (`harbor-core/src/trust.rs:662-1020`, 26 tests) — key expected reason strings: `suspicious-extension:.exe` (`:722`), season pack kept when `allow_season_packs` (`:732`), `trailer-or-extra` (`:747`), `no-playable-source` (`:757`), NZB-only stream kept (`:766`), `size-stub` (`:777`), `scam-score-7` (`:786`), disabled keeps everything (`:795`), `series-result-for-movie` for both episode and season-pack shapes (`:808, 821`), `cinema-bare-untagged` (`:835`), valid WebDl 1080p/2025 kept in cinema window (`:853`), fileIdx present skips episode check (`:870`), `addon-placeholder-banner` (`:881`), `addon-status-card` (`:890`), `addon-uncached-emoji` (`:901`), underscore trailer rejected (`:910`), `cinema-year-mismatch:2008-vs-2025` (`:919`), `fresh-cinema-fake-hdtv` (`:937`), 180 MiB 1080p episode: rejected non-anime `episode-stub-too-small-for-1080p` but kept with `is_anime` (`:955`), OVA short-format 80 MiB kept (`:973`), short-title guard `title-mismatch` for "DBM Obsession Viva Las Vegas" vs "Obsession" (`:985`), `title_matches("Rocky","Rocky II",1979,1976)` true (`:999`), tokenize("Amélie") = ["amelie"], ("Pokémon") = ["pokemon"] (`:1004`), camelCase `fileName` does not exempt status card (`:1010`).

**Scoring** (`harbor-core/src/scoring.rs:1306-1870`, 22 tests) — exact score assertions:
- 4K + HDR10 + HEVC + Atmos 8ch WEB-DL, empty opts/corpus → **score 36.0**, tier `UhdHdr`, reasons {4K, HDR10, HEVC, Atmos, "8.0 channels"} (`:1437`).
- 4K + DV+HDR10 (no audio extras) → **score 31.0** = 25 + 6, tier `UhdDv`, DV+HDR10 delta 6.0 (`:1462`).
- cached rd + MediaFusion → **88.0** = 60 + 20 (1080p) + 8 (strong-addon), reason "cached", no "easynews-direct" (`:1478`).
- Easynews+ addon → **84.0** = 60 + 20 + 4 (trusted-addon), signal "easynews-direct" (`:1495`).
- CAM 720p → **−72.0** = 8 − 80, tier ROUGH (`:1505`).
- Seeders: 5 seeders + hash → **20.0** (no boost); 0 seeders + hash → **−8.0** with both `zero-seeders-stale-meta` and `zero-seeders-soft`; 95 → **29.0** (+9); 500 → **30.0** (+10 cap) (`:1515`).
- Language: preferred `en`, English → **32.0** (+12); French → **6.0** (−14); empty → **17.0** (−3); Multi → **24.0** (+4) (`:1543`).
- Tier edges (`:1570`): DV→UhdDv, HDR10→UhdHdr, none→Uhd, 1080p+HLG→P1080Hdr, 720p→P720, 480p→SD, SCR→ROUGH, CAM 4K DV→ROUGH.
- rank_and_pick: cached 4K (90) beats uncached 1080p (30) and cached 720p (50) → primary 4K/90.0; byTier has 4K/1080p/720p; `all[0]` cached (`:1604`). No cached: 1080p (30) beats 4K (40) → primary 1080p (`:1648`). `respect_addon_order=true`: priority 0 / returnIdx 0 (score 30) ranks above priority 0 / returnIdx 1 (score 40) (`:1672`). CAM-only pool: primary falls back to non-theater 1080p (`:1706`).
- Corpus fractions: [CAM cached-rd, WebDl 100-seeders, HDTV 5-seeders, BluRay url] → trustedTrackedCount 3, trustedTrackedFraction 0.75, theaterCaptureFraction 1/3, webishFraction 2/3 (`:1730`); empty corpus all-zero (`:1756`); sizes [1,5,10,50,100] → median 10, p90 50 (`:1766`).
- PROPER → 21.0, delta 1.0; REPACK1 → 21.0/1.0; REPACK5 → 22.0/2.0 (`:1779`).
- Trusted group FLUX + remux + BluRay → **25.0** = 20 + 2 + 3 (`:1803`).
- `cam_in_filename_penalty`: 1080p WebDl with "HDCAM" in title → **−80.0** (20 − 100) (`:1813`).
- Addon priority: p0 → 32.0, p2 → 24.0, p5 → 20.0, none → 20.0 (`:1825`).
- `rank_and_pick` prefers higher-scored cached regardless of input order (80 vs 92 → 92) (`:1843`).
- Fresh window: dominated pool at day 50 keeps TS boosted (>0) and penalizes fake 4K WEBRip (<0) (`:1378`); non-dominated pool at day 50 → delta 0.0 (`:1413`).

### 7.2 TS fixture vectors — `src/lib/streams/__fixtures__/addon-samples.ts` (17 samples), verified by `verifyAddonSamples()` — `__fixtures__/verify.ts:12-24`
| # | Addon | Input markers | Expected |
|---|---|---|---|
| 1 | Comet | name `[TB⚡] Comet 1080p`, title `Show.Title.S01E01.1080p.WEB-DL.x264-GROUP 💾 5.43 GB 👤 42`, bingeGroup `comet|torbox|hash|file` | cached.tb, seeders 42 |
| 2 | Comet | `[RD⚡] Comet 4K`, `Movie.Name.2024.2160p.HDR.WEB-DL.x265`, bingeGroup `comet|realdebrid|…` | cached.rd, seeders 117, hdrFormat HDR10 |
| 3 | Comet | `[TB⬇️] Comet 1080p` | uncached.tb, seeders 12 |
| 4 | Jackettio | `[RD+] Jackettio 1080p` | cached.rd, seeders 87 |
| 5 | Jackettio | `[RD] Jackettio 1080p` (bare, no +) | uncached.rd, seeders 3 |
| 6 | Knightcrawler | `[AD+] knightcrawler\n720p` | cached.ad |
| 7 | Knightcrawler | `[RD download] knightcrawler\n1080p | HDR10` | uncached.rd, hdrFormat HDR10 |
| 8 | Torrentio | `[RD+] Torrentio\n1080p`, `👤 152 💾 2.1 GB` | cached.rd, seeders 152 |
| 9 | Torrentio | `[RD download] Torrentio\n4K` | uncached.rd, seeders 28 |
| 10 | MediaFusion | name `MediaFusion 🧲 TRB ⚡️ 2160p`, desc w/ videoSize 19,864,000,000 | cached.tb |
| 11 | MediaFusion | `MediaFusion 🧲 RD ⏳ 1080p` | uncached.rd |
| 12 | AIOStreams | `[RD+] AIOStreams\n1080p` | cached.rd, seeders 102 |
| 13 | AIOStreams | name `TorBox\n(Instant) (1080p)`, torbox.app URL | cached.tb |
| 14 | StreamFusion | name `⚡instant\nReal-Debrid` | cached.rd, seeders 220 |
| 15 | StreamFusion | `⬇️​download\nReal-Debrid` (ZWS-contaminated) | uncached.rd, seeders 7 |
| 16 | Easynews+ | url `https://easynews.com/dl/…`, videoSize 4,509,715,660 | resolution 1080p (no cache flags expected) |
| 17 | Easynews++ | url, videoSize 23,622,320,128 | {} (no assertions) |

`verifyAddonSamples()` only asserts fields present in `expected` (cached/uncached/seeders/source/resolution/hdrFormat/releaseGroup/size — `verify.ts:26-70`); `logVerificationReport()` prints pass/fail counts.

## 8. FACT vs INFERENCE

### 8.1 FACT (read directly from code)
- All regexes, weight numbers, floor tables, tier rules, rejection order, and function names cited above; every `file:line` reference was verified against the checked-out sources on 2026-09-02.
- The main TS pipeline parses with `parse-torrent-title`; the Rust core parses with its own `ptt_parse`. The Tauri fast path (`streams_run_pipeline`) performs **only** trust+score+rank on already-parsed streams.
- Rust `rank_and_pick` excludes theater sources from `primary`; TS `rankAndPick` does not. `preferAac` exists only in TS.
- Rust ranking counts any `url` as cached; TS requires `url && !hasUncachedMarker`.
- Rust parser lacks: TS's extra TS/TC lookahead source rules, the bare `\bWEB\b` source fallback, LATAM/Latin-American Spanish handling, AIOStreams generic cache markers, and the ElfHosted cache rule. TS parser lacks nothing the Rust parser has except the Rust-exclusive `check_word_isolated` mediafusion slug isolation behavior (TS uses `(?!\w)` lookaheads instead — `parser-cache-flags.ts:156-168`).
- `allowSizeOutliers`, `preferredAudioLangs`, `requirePreferredLanguage`, `inTheaters`, `ANIME_JA_RX` are declared but unused by the engine logic.
- Rust corpus stats include median/p90/p10 percentiles not present in TS `CorpusStats`; neither implementation consumes them in scoring.
- Live debrid cache resolution (cacheCheck/listLibrary), anime enhancement, and the early-leak rescue exist only in the TS pipeline — they are absent from the Rust wasm one-shot `run_pipeline_pure_js`.

### 8.2 INFERENCE (reasoned, not directly asserted in code)
- The Rust core is the "intended canonical" engine (comments in `parser.rs`/`trust.rs`/`scoring.rs` headers say "Mirror of src/lib/streams/*.ts", and the Tauri path is preferred when available — `pipeline.ts:216-235`), but the mirrored TS versions are NOT automatically kept in sync; the divergences listed in §2/§4.7 are evidence of drift rather than deliberate difference.
- The 51-entry trusted-group list (identical in three places: `parser.rs:8-22`, `scoring.rs:27-36`, `parser-trusted-groups.ts:1-52`) appears duplicated rather than shared, creating a maintenance hazard; no test asserts the three copies are equal.
- The unused `p10/p90/median` corpus percentiles suggest a planned-but-not-implemented size/health-based scoring stage.
- `PREFER_AAC` being defined as "browser only" (`pipeline.ts:12`) implies the AAC preference exists to work around browser (HTML5) audio limitations; native playback therefore never gets the AAC preference.
- The rescue heuristic (`pipeline.ts:17-46`) exists specifically to recover false-positive `fresh-cinema-fake-*`/`new-release-stub` rejections for leak scenarios in the 90-day cinema window; it runs after both native and JS paths (hence `finalizeWithRescue` wrapping both).




