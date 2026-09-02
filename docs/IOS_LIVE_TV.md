# IOS Live TV (IPTV / EPG / Catch-up)

> Strategy doc. Behavior source: `docs/audit/live-tv-dvr.md` (verified against Harbor v0.9.21). Portable parsers are Windows-testable per spec §14–15.

## 1. Playlist model (parity)

- `iptvPlaylists[]` in settings: `{id, name, url, epgUrl?, kind: m3u|xtream|epg, xtream?: {server, username, password}}`. IDs `pl-{ts}-{rand}`.
- Add/Edit/Delete/Refresh/Reorder + **stale-while-revalidate (6h TTL)** + full state purge on delete.
- **Export M3U only** (attr passthrough whitelist: tvg-id/logo/chno/shift/language/country/duration/catchup/catchup-source/duration −1, quoted-escape). **No EPG generation** (FACT — Harbor doesn't have it; we don't build what Harbor doesn't have).
- **Security divergence (documented):** Harbor stores Xtream credentials in cleartext localStorage. iOS stores them in **Keychain** (spec §87 — we never regress security even for parity).

## 2. M3U parser (port exact rules — Windows-testable)

- BOM strip, CRLF split, `#EXTM3U` ignored.
- Directives: `#EXTINF`, `#EXTGRP` (sticky), `#EXTVLCOPT` (http-user-agent → vlcopt-ua, http-referrer → vlcopt-referrer), `#KODIPROP` (adaptive license_type/key).
- Quote-aware EXTINF tokenizer; duration = first unquoted token; title after first comma following last closing quote.
- URL pipe-options: user-agent / referer|referrer / cookie (first-wins, URL-decoded).
- Channel id `{base}::{tvg-id||tvg-name||title||ch-N}::{autoIndex}`.
- **Decorative-row filtering** (2 layers: parse-time symbol-only rows + display-time >55% symbol divider rows) — critical for real playlists.
- `deriveEpgUrls` for get.php/player_api.php URLs.

## 3. Xtream Codes client (parity)

- URL credential parsing (`get.php`/`player_api.php` with user+pass only).
- `player_api.php?username&password&action=…`, UA `IPTVSmartersPro/3.1.5`, strict JSON (HTML/XML → XtreamAuthError).
- Account check: `user_info.auth===0` → fail; status expired/banned/disabled → typed errors; **https-port stream-base swap** via `server_info.server_protocol`.
- Live: categories + streams in parallel; `tvgId=epg_channel_id`; URL `{base}/live/{u}/{p}/{id}.{ts|m3u8}`; container pick vs `allowed_output_formats` + `iptvLiveContainer` (default ts); `tv_archive>0` → catchup=xtream + catchup-days.
- Short EPG (`get_short_epg`, limit 8) with guarded base64 title decoding — fallback for ≤120 channels.
- VOD + Series: movie channels (`tvg-type=movie`), series info → episode channels S{ss}E{ee} URLs, per-source in-memory cache.
- Batch publishing (256/batch, yield) for huge catalogs.

## 4. XMLTV parser (port — streaming, Windows-testable)

- Streaming block parser (no DOM): scan `<channel`/`<programme` tags, incremental, 64-char leftover buffer.
- Limits: 200MB payload, 30s connect, 25s stall, gzip magic sniff, ≤5 redirects, VLC UA, progress ≥3s.
- `parseProgramme` (start/stop/channel required; drop end≤start), time `YYYYMMDDHHMMSS ±HHMM` → epoch UTC, entities + CDATA.

## 5. EPG subsystem (parity)

- Model: `EpgProgram{channelTvgId,title,description,startMs,endMs,category,iconUrl}`, `EpgIndex{byChannel, channelMeta, fetchedAt}`.
- Per-playlist in-memory cache (1h TTL), progressive indexing, multi-URL fallback (first with ≥1 program), URL priority: playlist epgUrl → derived Xtream → EPG-only sources.
- **Channel↔EPG resolution**: user override → direct tvgId → **ambiguity guard** (shared tvg-id + name-token validation) → normalized display-name fallback (Arabic-normalized) → per-channel tvg-shift + global offset.
- Manual matching UI (`EpgMatchModal` equivalent: pick tvg-id, override, clear).
- Xtream short-EPG fallback for empty base EPG.
- **UI: fixed 8-hour now-anchored window** (parity — Harbor has NO date navigation, FACT), 30-min ruler, now-line ~1/3 from left, program blocks with live/past+replay/future states, lazy virtualization, Arabic-aware search (harakat stripping + أإآٱ→ا etc. — port `rtl.ts` normalization).

## 6. Catch-up (exact URL transforms — parity-critical #1)

Detection: attrs `catchup`/`catchup-type` → `catchupSource` → URL shape (Xtream live regex auto-detect). Types: default/append/shift/flussonic/xtream.

| Type | Transform |
|---|---|
| flussonic | path match `/([^/]+).(m3u8|ts|mpd)$` → `{dir}/{stem}-{start}-{duration}.{ext}` (mpegts/mono → index); else `{path}/archive-{start}-{duration}.ts` |
| xtream | `{host}/timeshift/{u}/{p}/{ceil(dur/60)}/{Y-m-d:H-M UTC of start}/{id}.ts` |
| catchupSource present | absolute URL → template-fill; else append `?/&` + source |
| fallback | `{url}?utc={start}&lutc={now}` |

Template tokens: `{start}{utc}{timestamp}` `{end}{utcend}` `{now}{lutc}{timenow}` `{duration}{dur}` `{offset}` `{duration-minutes}` + strftime `${utc:FMT}` with Y m d H M S (UTC, zero-padded). `append`/`shift` have no dedicated branches (FACT). `catchup-days` parsed but never enforced (parity: don't enforce either).
Playback headers (UA/Referer/Cookie from channel) carried into player for live + catch-up.

## 7. Channels UX (parity)

- Group relevance ordering (region tokens first, UI-language scoring, neutral bumps), pin/hide groups, per-source prefs.
- Favorites (snapshot store surviving source removal, virtual `__FAVORITES__` landing group, legacy migration).
- Pins (ordered) → pinned → most-watched(≥3) → rest. Play stats (600-entry LRU). Country detection + filtering + flagcdn logos. Channel hydration from Cinemeta (7-day TTL, 5000 LRU, skip news/sports). Top-networks home row (curated regexes).

## 8. Sports (ESPN live scores — port)

- ESPN site API (`site.api.espn.com/apis/site/v2/sports`), **Saudi Pro League first** in league list, parallel scoreboards, in-memory cache + inflight dedupe, 12s polling, sort in-progress→pre→post, match summary (lineups/stats/events/formations), MMA special-case via `sports.core.api.espn.com`. It's a scoreboard companion, NOT a stream finder (parity: no channel mapping).

## 9. Windows-testable surface

M3U parser, Xtream URL building (pure functions), XMLTV block parser, catch-up URL transforms (all 5 types + template tokens), EPG resolver (ambiguity guard + name matching + shift math), decorative-row filters, Arabic normalization. Golden vectors recorded from Harbor behavior → `scripts/parity/`.
