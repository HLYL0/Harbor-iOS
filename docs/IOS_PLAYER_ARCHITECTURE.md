# IOS Player Architecture

> Player feasibility study + design (spec §45). All facts about Harbor behavior come from `docs/audit/player.md` (code-verified); iOS facts from our verified MPVKit build + Apple platform rules.

## 1. Harbor player model (what we must reproduce)

Harbor's player = React UI + `PlayerBridge` interface + two engines: **mpv** (libmpv embedded) and **html5** (`<video>` + hls.js/mpegts.js), with orchestration (retry, resume, auto-next, sleep timer) in framework-independent hooks. mpv is the source of truth for state.

Engine selection rules (Harbor, `use-player-bridge.ts` / `player-utils.ts`):
1. `playerEngine` setting: auto (default) / mpv / html5.
2. auto → desktop/notWebReady → mpv if probe OK, else html5; web → html5.
3. **Live-like sources (iptv:, non-movie/series/anime) → html5 regardless** (HLS resilience).
4. Post-error auto-fallback html5→mpv on `decode`/`codec`/`noAudio` (once per session).

## 2. iOS engine mapping (evidence-based)

| Harbor | iOS | Why |
|---|---|---|
| mpv engine | **MPVBackend** (MPVKit, verified on device) | same libmpv family → same options, sub styling, codecs, speed, A/B loop |
| html5 engine | **AVPlayerBackend** (AVPlayer + AVKit) | system HLS/mpegts quality, native PiP/AirPlay, best live resilience — mirrors Harbor's "live→html5" preference |
| engine=auto | same rule: live → AVPlayer; VOD/notWebReady → MPV; probe failure → AVPlayer | parity + resilience |
| html5→mpv error fallback | decode/codec failure on AVPlayer → rebuild as MPV (once/session) | same logic, same triggers |

Selection logic lives in ONE place: `PlayerEngineResolver` (port of `pickBridge` + `use-player-bridge` rules as pure, unit-tested Swift).

## 3. Backend capabilities matrix (validated/planned)

| Capability | MPVBackend | AVPlayerBackend |
|---|---|---|
| MKV/AVI/WebM/DASH/MPEG-TS (direct) | ✅ verified (MVP) | ⚠️ container-dependent |
| Header-authenticated sources | ✅ verified (MVP) | ✅ `AVURLAssetHTTPHeaderFieldsKey` |
| HLS (VOD + live) | ✅ | ✅ native (preferred for live) |
| SRT/VTT/ASS/SUB | ✅ libass (ASS full fidelity) | ✅ text formats, limited ASS |
| Image subs (PGS/VOBSUB/DVDSUB/DVB) | ✅ mpv-side | ❌ |
| Track switching (audio/video/sub) | ✅ | ✅ (media selection) |
| Sub styling (font/size/color/border/margin/align/ASS override) | ✅ full mpv property set | ⚠️ limited (AVFoundation rules) |
| Sub delay ±, auto-sync | ✅ | ⚠️ delay only |
| Speed 0.25–3.0, A/B loop, panscan/zoom/aspect | ✅ | ⚠️ speed only |
| HW decode | ✅ videotoolbox | ✅ |
| PiP | ⚠️ UNKNOWN (MPVKit→sample-buffer PiP) | ✅ native |
| AirPlay | ⚠️ indirect (system mirroring) | ✅ native route |
| Now Playing / lock screen | ✅ (we drive MPNowPlayingInfoCenter ourselves) | ✅ |
| Frame capture / screenshots | ✅ mpv screenshot | ✅ |
| Anime4K user-shaders | ✅ glsl-shaders | ❌ |
| Statistics overlay | ✅ mpv stats props | ⚠️ AVPlayer item access log |

**Decision:** VOD/torrent/header/direct → MPV. Live HLS/MPEG-TS and PiP-critical flows → AVPlayer. User-visible override matches Harbor's `playerEngine` setting (auto/mpv/html5 → auto/mpv/avplayer in our UI naming).

## 4. mpv option set (port of Harbor's, adapted)

### Pre-init (MPVKit): same semantics as `apply_pre_init` (`mpv.rs:320-460`)
- `user-agent` from source headers or VLC UA; `http-header-fields` from behaviorHints
- `hwdec=videotoolbox` (Harbor's mac-embed choice; iOS equivalent)
- `input-default-bindings=no`, `input-media-keys=no`, `osc=no`, `osd-level=0`
- `volume-max=600`, `cursor-autohide=200`, `background=color`
- `start=<seconds>` for resume

### Post-init (`mpv_start`): non-live and live block sets ported as-is
- non-live: `cache-secs=300`, `demuxer-max-bytes=512MiB`, `demuxer-max-back-bytes=64MiB`, `demuxer-readahead-secs=300`, `network-timeout=600`, `stream-lavf-o=reconnect=1,...`, `stream-buffer-size=32MiB`, cache dir → app cache
- live: 30s/64MiB/16MiB/20s/60s/16MiB variants
- subs: `sub-fonts-dir` → app fonts dir, `embeddedfonts=yes`, sub style properties from `sub-style.ts`
- HDR-to-SDR block (`hdr_to_sdr`, default on in Harbor): `tone-mapping=spline`, `gamut-mapping-mode=perceptual`, `hdr-compute-peak=yes`, `hdr-contrast-recovery=0.30`, `hdr-peak-percentile=99.995`, `dither-depth=auto`, `target-trc=bt.1886`, `target-prim=bt.709` — valid on iOS (EDR display path)

### Property allow/block lists (security port)
Harbor blocks `script*`, `load-scripts`, `ytdl-raw*`, `screenshot-directory/template`, `sub-add` from UI input. **We port the identical blocklist** — parity AND security (spec §87).

## 5. Orchestration ports (constants identical to Harbor)

| Module | Constants (from audit, FACT) |
|---|---|
| Resume | tick 4s; min 5s; stub cap 150s; watched ratio **0.85** |
| Retry ladder | MAX_AUTORETRY_ATTEMPTS=5; live reconnect 1.5s/4s delays |
| Stall/freeze | slow-load 50s; frozen 75s/18s; black-screen 6s (20s p2p); stuck 18s; room stall 9s |
| Stream switch | in-place, position-preserving, serialized by StreamSwitchGuard |
| Auto-next | duration>150s, not started near end (ratio 0.8), UpNext cancel card |
| Sleep timer | 15/30/45/60/120/180/240/360 + end-of-episode modes |
| Chrome auto-hide | playing 1800ms / paused 4500ms / resume 1000ms |

**iOS retry ladder adaptation** (Harbor's steps 4–5 need a local proxy/transcode server we don't run):
live-reconnect → debrid failover (different debrid service) → same-URL reload → **picker escalation** (attempt+1, capped 5). The proxy/transcode steps are documented as desktop-only in `IOS_PLATFORM_GAP.md` (no silent drop, spec §102).

## 6. Subtitles (per audit §5)

- Formats SRT/VTT/ASS/SUB + image subs (mpv-side). **Dual subtitles: NOT in current Harbor (FACT)** → parity target = single track; do not build dual.
- Download pipeline port: encoding normalization (BOM strip; UTF-16→UTF-8; **windows-1256 default for Arabic** — critical for LO), content sniffing, 15s timeout.
- Style: full property set + style presets (incl. Arabic preset forcing ASS override + Noto Sans Arabic).
- Auto-sync: port Rust `subsync/*` (speech intervals + FFT cross-correlation, ratios, NCC thresholds) → Swift or vendored Rust; opt-in `subtitleAutoSync` (default false, same as Harbor).
- Providers: wyzie / opensubtitles / jimaku / addon-provided (same search surface).

## 7. Skip intro/outro (per audit §6)

- AniSkip v2 API, TheIntroDB v2 API, chapter-title classification, **Harbor ad-corpus feed (Ed25519-verified via CryptoKit)** — all portable as-is; in-memory caches + inflight dedupe; merge priority `[ad, aniSkip, introDb, chapters]`, 2–360s segments, outro after 50%, 0.75s tail margin. Manual pill (Harbor has no auto-skip — FACT).

## 8. Trickplay (per audit §4)

- Harbor: shadow-mpv screenshot scheme, 2s buckets, 240px width, jpg q72, LRU 160 entries/48MiB, session-only.
- iOS: same UX contract (192×108 preview card, nearest-bucket, 60% opacity fallback). Generation backend: **AVAssetImageGenerator for AVPlayer path; MPVKit screenshot for mpv path** — bounded, cancellable, background-priority. No persistent cache in v1 (matches Harbor).

## 9. Multiview (per audit §7)

- Harbor: Windows-only, ≤4 external mpv processes, single audio focus. 
- iOS: **2–4 in-process MPVKit sessions** (no child processes on iOS). Device-aware: 2 tiles everywhere; 3–4 only on ≥A17 devices after decode-capability probe. Audio focus = exactly one unmuted session (parity with Harbor). Windows-only in Harbor means we have design freedom; do not fake parity with desktop.

## 10. Statistics + diagnostics

Port the stats rows: engine, dwidth×dheight, fps (estimated-vf-fps fallback), codecs, hwdec, bitrates, dropped frames, cache %, tracks, speed, volume. mpv props available via MPVKit; AVPlayer path uses AVPlayerItemAccessLog.

## 11. Explicit non-goals (documented in IOS_PLATFORM_GAP.md)

SVP frame interpolation, RTX HDR, built-in transcode server, external mpv processes, Discord Rich Presence. Each replaced or dropped with written justification.
