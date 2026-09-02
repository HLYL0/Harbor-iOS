# IOS Repository Audit

> Phase 0 deliverable. Source of truth: the live `harborstremio/harbor` repository at audit time, plus deep-dive reports in `docs/audit/`.

## Audit snapshot

| Item | Value |
|---|---|
| Harbor version | **0.9.21** (`package.json`, `Cargo.toml`) |
| Latest release | V0.9.21 (2026-07-11) |
| Reference commit | `0117755` (main at audit time, 2026-09-02) |
| License | MIT |
| Frontend | React 19 + TanStack Router/Query/Virtual + Tauri 2 + Vite + Tailwind 4 |
| TS/TSX files | ~1,568 (769 `.ts` + 799 `.tsx`); 573 files in `src/lib` (framework-independent logic) |
| Rust backend | `harbor-core` (parser/trust/scoring/types) + `src-tauri` ≈ 19.5K LOC |
| Package manager | pnpm 11.9.0 |

## Repository topology (audited)

```
harbor/
├── harbor-core/          Rust: canonical stream parse → trust → score → rank
├── src/
│   ├── lib/              framework-independent TS business logic (44 modules)
│   ├── components/       React UI (player, catalogs, search, anime-hero, …)
│   ├── chrome/           sidebar / siderail / minui-dock / cinematic-overlay
│   ├── router/           TanStack Router tree (rooms + routes)
│   └── assets/           fonts, awards, addon logos, flags, theme previews, …
├── src-tauri/
│   ├── src/              Rust native: mpv, cast (Cast/DLNA/Roku/AirPlay), dvr,
│   │                     download, thumbs (trickplay), subsync, anime4k, svp,
│   │                     transcode, stream_proxy, web_server, cf_relay,
│   │                     discord_rp, pip, hdr_overlay, multiview, torrent_engine
│   ├── vendor/rust_cast/ vendored Chromecast implementation
│   ├── libmpv/           bundled libmpv headers
│   └── relay/            Cloudflare relay package
├── tests/                30 node --test suites (player, iptv, keyboard, RTL, …)
├── docs/, examples/, scripts/, flatpak/
└── docker-compose.yaml   (relay/web deployments)
```

## Module map (src/lib — 44 modules)

`addons-store`, `ad-report`, `anilist`, `arabic`, `avatars`, `awards`, `cast`,
`catalog-page`, `debrid`, `discord`, `discover`, `download`, `dvr`, `feed`,
`hover-preview`, `i18n`, `iptv` (37 files: M3U/XMLTV/Xtream/EPG/catch-up/VOD),
`lists`, `local-library`, `mal`, `multiview`, `player` (mpv + html5 fallback +
subsync + presets + rtx-hdr + svp + anime4k + motion interp), `player-shells`,
`privacy`, `providers` (TMDB, Kitsu, AniZip, Jikan, OMDB, RPDB, Fanart, mdblist,
streaming availability, Cinemeta, IMDB), `query`, `region`, `remote`, `settings`,
`simkl`, `skip-intro`, `sports`, `streams` (parser/scoring/trust/pipeline),
`stremboxd`, `subtitles`, `theme-import`, `together`, `torrent`, `trakt`,
`updater`, `wrapped`.

## Rust module map (src-tauri/src)

`airplay`, `anime4k`, `binary_lookup`, `browser`, `cast`, `cast_hls`,
`cast_server`, `cast_subs`, `cf_relay`, `crash_report`, `discord_rp`, `dlna`,
`download`, `dvr`, `fonts`, `fullscreen`, `hdr_overlay`, `http_fetch`,
`local_lib`, `modal_overlay`, `mpv`, `mpv_render_linux`, `mpv_render_mac`,
`multiview`, `pip`, `pip_mac`, `power`, `proc_mem`, `process`, `roku`,
`settings_store`, `song_id`, `stream_proxy`, `streams`, `stremio_auth`,
`sub_extract`, `subsync/*` (correlate/extract/moviehash), `svp`, `thumbs`,
`torrent_engine/*` (cache_sweep, dht_boot, netcheck, selftest, stream_route,
trackers), `trailer`, `transcode`, `tray`, `web_server`, `webview_helpers`.

## Active development at audit time (open PRs, most recent first by update)

| PR | Topic | Parity impact |
|---|---|---|
| #950 | **Native mobile & TV client (Flutter) — iOS/iPadOS/Android/TV** | Harbor itself is building a mobile client; inspect as behavior reference |
| #642 | Android support | — |
| #965 | Harbor Sync: optional E2E-encrypted cross-device sync | new sync surface |
| #934 | Watch Together relay setup improvements | watch-party |
| #1028 | Player queue navigation + "Still Watching" | player |
| #1030 | Windows media controls | platform |
| #1032 | ASS subtitle normalization | subtitles |
| #1033 | Ambient screensaver | UI |
| #1034 | Beta translations | i18n |
| #1045 | Background download manager (ported from beta) | downloads |
| #1047 | Harden local attack surface | security |
| #1017 | Manga + mobile companion + remote (ported from beta) | new rooms |
| #1029 | Embedded HDR EDR path on macOS | HDR |
| #1091/#1092 | Secondary subtitle slot fixes | dual subs |
| #1119 | Season pack source lock across episodes | streams |
| #1155 | MAL absolute pagination URLs | anime |
| #1190 | Localized hero metadata toggle | metadata |
| #1191 | Picture presets as fixed settings (not cumulative) | player |
| #1192 | Size parsing with comma/space separators | stream parser |

## Deep-dive reports

| Report | Scope |
|---|---|
| `audit/stream-engine.md` | parse→trust→score→rank, signals, weights, test vectors |
| `audit/player.md` | player features, mpv options, trickplay, subs, intro/outro, multiview |
| `audit/stremio-addons.md` | auth, addon protocol, discovery store, deep links |
| `audit/metadata-anime.md` | providers, anime pipeline, awards, discover personalization |
| `audit/live-tv-dvr.md` | M3U/Xtream/XMLTV/EPG/catch-up/DVR (real vs stubbed) |
| `audit/themes-i18n.md` | themes, Theme Studio, custom code sandboxing, i18n, RTL |
| `audit/casting-together.md` | Cast/DLNA/Roku/AirPlay, Watch Together, relay |
| `audit/sync-storage.md` | Trakt/Simkl/MAL/AniList, debrid, downloads, storage, backup, security |
| `audit/rooms-ui.md` | routes, rooms, rails, chrome modes |

## Methodology

- Cloned `main` at commit `0117755` (shallow 100) on 2026-09-02; re-clone/refresh before every milestone (see `HARBOR_DELTA_REPORT.md`).
- All findings are FACT-cited to file paths; inferences are labeled.
- Re-run audits when: a new Harbor release lands, a beta-only feature is merged to main, or an open PR above merges.
