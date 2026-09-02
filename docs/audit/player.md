# Harbor PLAYER Subsystem — Forensic Report

Scope: the complete playback stack of Harbor (Stremio client, Tauri 2 + React/TS + Rust + libmpv).
Source: repo clone inspected at `C:/Users/Admin/AppData/Local/Temp/harbor-ref` (paths cited relative to repo root).

Architecture in one paragraph: React owns the UI; two interchangeable `PlayerBridge` implementations (`src/lib/player/mpv.ts`, `src/lib/player/html5/bridge.ts`) implement a common interface (`src/lib/player/bridge.ts`). A Tauri Rust layer (`src-tauri/src/mpv.rs`) embeds libmpv (libmpv2 crate) and forwards mpv events/properties to the webview over `mpv://event`. All player orchestration logic (retry, resume, auto-next, sleep timer, etc.) lives in React hooks under `src/views/player/hooks/`. mpv is treated as the source of truth for playback state (per `AGENTS.md`).

---

## 1. Complete Player Feature Inventory

### 1.1 Engine selection & bridge lifecycle
- Two engines: `html5` (in-webview `<video>` + hls.js + mpegts.js) and `mpv` (embedded libmpv). Settings: `playerEngine: "auto" | "html5" | "mpv"` (default `auto`) — `src/lib/settings/defaults.ts:155`.
- `pickBridge()` in `src/views/player/player-utils.ts:53-87`: `auto` probes libmpv via `mpv_probe`; on desktop (`__TAURI_INTERNALS__`) or when `notWebReady===true`, mpv is preferred; if the probe fails it falls back to html5 with a console warning. Live-like sources (IPTV or non-movie/series/anime types) default to html5 unless `notWebReady` — `src/views/player/hooks/use-player-bridge.ts:82-87`.
- **Auto-fallback html5→mpv**: in `use-player-bridge.ts:156-165`, when engine is html5, `playerEngine === "auto"`, and the snapshot reports `errorCode` `decode`/`codec` or `noAudio`, Harbor probes mpv; if available it rebuilds the bridge key, recreating the player as mpv (one shot via `autoFallbackTried`).
- mpv can run **embedded** (Windows child-HWND behind the WebView, macOS `NSOpenGLView` render API, Linux `GLArea` render API; `vo=libmpv`) or in **its own window** (`playerMpvEmbed` setting, default true). Non-embedded mode: mpv window is `ontop=yes`, `border=no`, geometry tracked via `mpv_set_geometry` (`src-tauri/src/mpv.rs:1122-1186`); embed geometry tracking in `src/lib/player/mpv.ts:396-450` (resize/move observers, `harbor:mpv-force-geom` event).
- Bridge key incorporates engine/anime4k/embed/svp so any change tears down and rebuilds the bridge — `use-player-bridge.ts:88`.

### 1.2 Core transport
- play/pause (tap vs hold-to-fast-forward: holding the play/pause key >350ms sets rate ≥2×, releasing restores; `use-keyboard-shortcuts.ts:141-153,385-404`).
- Seek absolute-exact via `seek <sec> absolute exact` (mpv) / `currentTime` (html5). Seek clears sub-text/sub-start.
- Frame stepping `frame-step`/`frame-back-step` (mpv) and ±1/24s currentTime step (html5).
- Volume: mpv `volume` 0-600 scale (`volume-max=600`, `src-tauri/src/mpv.rs:387`) exposed 0-6×; html5 clamps 0-1(6); volume SFX optional; per-media volume persisted (`player-volume`).
- Speed 0.25-3.0 in 0.25 steps (`playerSpeedDown/Up`), persisted per meta (`writePlayerPrefs(metaId,{rate})`).
- Digit seek 1-9 = 10%-90% of duration; `0` = start; Home/End.
- Panscan (`panscan`), zoom (`video-zoom`), aspect override (`video-aspect-override`), stretch (`keepaspect=no`), crop/contain/fill object-fit cycles — `use-video-fill.ts`, bridge `setPanscan/setVideoZoom/setAspectOverride/setStretch`.
- Video EQ via `setVideoEq(name,value)` (raw mpv property passthrough from a UI menu).
- Subtitle cycle key (`playerSubtitleCycle`/Alt), remembers last sub choice in player prefs (`use-playback-controls.ts:36-62`).
- Chapters list surfaced in snapshot (`chapter-list` observed).
- PiP (two forms — see 1.11), Fullscreen, Cast, DVR, EPG — see below.
- `force-media-title` for media title/artist/artwork (MediaSession on html5).
- Screenshot: mpv `screenshot-to-file` PNG (sw renderer, png compression 3, polls up to 3s for file — `src-tauri/src/mpv.rs:1365-1398`); html5 draws video to canvas and writes via plugin-fs or triggers download.
- Frame capture toast + "Open folder" (`quick-tools.tsx`); GIF recording (mpv JPG frames at 50ms, max 600 frames, ffmpeg palettegen/paletteuse two-pass, 640px wide, 2-30fps — `src-tauri/src/mpv.rs:1400-1626`); **Clip recording** (re-encodes last N seconds via external mpv binary: `--start/--length/--o=out.mp4 --ovc=libx264 preset=veryfast crf=18 --oac=aac b=192k`, optional subtitle burn-in via `--sub-files`/`--sid` — `src-tauri/src/mpv.rs:1634-1730`).
- A/B loop: `ab-loop-a`/`ab-loop-b` properties (mpv), timeupdate watch loop (html5); keys `I`/`O`/`L`; UI chip in quick-tools.
- Sleep timer (see 1.13).
- Media keys (MediaPlayPause/TrackNext/TrackPrevious).
- Hold-to-FF state indicator (`holdSpeedActive`).
- Pause on minimize (default on) / pause on unfocus (default off) — `use-pause-on-inactive.ts`; auto-resume when window refocuses only if auto-paused.

### 1.3 Retry / stall / freeze detection (`use-auto-retry.ts`, constants `player-utils.ts`)
Ladder (only for non-live, non-local; live handled separately):
1. **Live reconnect**: live sources reload the same URL on errorCode — 1 attempt if never played (1.5s delay), 2 if it played (4s delay); after that mpv's own reconnection is trusted (`use-auto-retry.ts:110-130`).
2. **Debrid failover**: if stream has `infoHash` + debrids configured → resolve same hash through debrids and `b.load()` new URL (optionally via local stream proxy).
3. **Same-URL reload** (once).
4. **Local stream proxy retry** (once) — register URL in `stream_proxy.rs` and reload through 127.0.0.1.
5. **Transcode rescue** (once) — register with `transcode:true` (ffmpeg remux to MPEG-TS) and reload with `notWebReady:true`.
6. **Stremio-server p2p transcode** (opt-in `stremioServerTranscode`) for `decode` errors on the bundled engine — destroys bridge, loads `transcodedUrl`.
7. **Picker escalation**: `openPicker` with `attempt+1` (bounded by `MAX_AUTORETRY_ATTEMPTS = 5`); if `instantPlay` is off, it first probes source HTTP status (`bytes=0-1` Range GET) and shows a SourceErrorCard instead of auto-advancing.

Stall/freeze detectors:
- **Slow load**: no duration + no progress after `SLOW_LOAD_MS = 50_000` → `slowLoad` flag (UI: stream-loading bar / header warning).
- **Frozen position**: position < 5s frozen for 75s if never started, 18s if started (`graceMs` logic), polled 1s.
- **Black screen**: status playing but `videoWidth/Height` never > 0 for `BLACK_SCREEN_GRACE_MS = 6000` (or 20s for p2p engine).
- **Stuck on load**: duration 0 and position 0 after `STUCK_AUTORETRY_MS = 18_000`.
- **Room stall**: in Together rooms, no video after `ROOM_STALL_MS = 9000`.
- **P2P engine**: no peers/no progress after `ENGINE_FIRST_FRAME_GRACE_MS = 20_000`; hard ceiling `ENGINE_HARD_CEILING_MS = 75_000` when downloadSpeed 0, unchoked 0, no recent bytes, no video.
- **Stub detection** (`use-stub-detection.ts`): when instantPlay is on and the source reports a suspiciously short duration (< `SHORT_PLAYBACK_SEC`, dead-streams module) vs. metadata runtime, marks the stream dead (TTL) and ejects back to the picker.
- **Wake reconnect** (`use-wake-reconnect.ts`): detects main-thread gap > 30s (system sleep) and reloads the stream at the last position.
- **mpv-native failure** (`src-tauri/src/mpv.rs:809-958`): event loop error backoff (40ms doubling, cap 1s); after 12 consecutive poll errors emits `player-failure` (reason `persistent-event-errors`); raw -13/-16 errors mapped to `end-file reason=error`. Frontend `mpv-failure.ts` maps to `status:"error"`, `errorCode:"unknown"`.
- **end-file handling** (`src/lib/player/mpv.ts:254-271`): reasons `stop`/`quit`/`redirect` ignored; `eof` → `ended`; anything else → `error` with `errorCode:"decode"`. `suppressEndFileUntil` suppresses stale end-file during in-place reload (1.5s window).

### 1.4 Stream switching (`use-stream-switcher.ts`, `stream-switcher.tsx`, `stream-check-pill.tsx`)
- "Is this stream ok?" pill auto-opens once per session after 1.5s of playback, auto-dismisses after 5.5s.
- In-place switcher overlay (never navigates to full picker — prevents unmount/stop bug). Picker cache pinned for the session.
- Swap: pauses current stream, resolves new one, proxies headers via stream proxy, loads preserving position (`current` if > 5s and not a stub, else saved resume), plays, saves new stream as playback history.
- `StreamSwitchGuard` serializes concurrent swaps; aborts superseded ones; resume-on-failure restores old stream playback.

### 1.5 Resume & progress persistence (`use-resume-autosave.ts`, `src/lib/resume.ts`, `resume-prompt.tsx`)
- Ticks every 4s while playing; forces save on pause/end/error/unmount/pagehide/beforeunload.
- Minimum position 5s; no saves for durations < `STUB_MAX_SEC = 150`; deduped (1.5s delta).
- Watched threshold: `WATCHED_RATIO = 0.85` (also `WATCHED_THRESHOLD = 0.85` in `src/lib/episode-progress.ts:10`); ended status always counts as watched.
- Writes: resume ms, playback history (stream + URL + title), manual-watched set, local continue-watching, AniList/MAL watching + completed progress, taste events ("play"/"watched").
- Resume prompt UI ("Keep Watching" / "Start Over", kids variant) — `resume-prompt.tsx`.

### 1.6 Auto-next episode (`use-auto-next-episode.ts`) & end-of-playback (`use-auto-end-exit.ts`)
- Auto-next fires when: setting `autoPlayNextEpisode` (default true), a next episode exists, host/solo (canChangeEpisode), duration > 150s, did NOT start within last 20% (`use-started-near-end.ts`, ratio 0.8), and one of: natural `ended`, error within last 2s, or position ≥ duration-1s while not playing. Cancelled via UpNext countdown card; sleep timer/queue armed suppresses auto-next.
- End-exit: closes player 800ms after end when no next episode; live channels auto-reload up to 5× per 15s window instead.

### 1.7 Skip intro/outro/recap/ad (see §6 for providers; UI `skip-pill.tsx`)
- Segments merged by priority `[adCorpus, aniSkip, introDb, chapters]` with overlap rejection, sorted; filtered to 2-360s, outro only after 50% of duration; capped at duration.
- `activeSegment` requires position ≥ start and < end-0.75s.
- Skip pill: "Skip Intro" / "Skip Credits" / "Skip Recap" / "Skip injected ad?"; outro+next → "Next Episode" with countdown (default lead 15s) + UpNext card; ad pill styled differently (rose border). Auto-skip settings not in pill itself — pill is manual (FACT: pill button calls `onSkip`; auto-skip setting not found in inspected files).
- Segment badges shown in seek-bar thumb preview (OP/ED/Recap/Ad).

### 1.8 HUD & controls (`src/components/player/transport.tsx` + shells)
- Transport variants: `transport.tsx` (default), `transport-stremio.tsx`, `transport-kids.tsx`; `minimal-shell.tsx` shell; theme `playerChromeTheme` auto/default/stremio.
- HUD: seek bar (with skip-segment markers via thumb preview labels), play/pause, ±10/±30s, prev/next episode, audio menu (`audio-menu.tsx`: track selection, audio normalize toggle, audio profiles bass/voice/bass-reduce/night via lavfi AF chains `mpv.ts:79-84`, audio delay, audio device), subtitle menu (`subtitle-menu.tsx`: tracks, providers wyzie/opensubtitles/jimaku/addons, sub style bar, sub sync bar, delay), settings, cast menu (`cast-menu.tsx`, `cast-modal/`), stream switcher, episode panel (`episode-panel/`), PiP, fullscreen, volume indicator, sleep timer control, quick tools (A/B chip, frame/gif/clip toasts), stats overlay (I key), Anime4K indicator (`anime4k-indicator.tsx`), SVP indicator (`svp-indicator.tsx`), P2P status chip (`p2p-status-chip.tsx`), stream check pill, live channel overlay (`live-channel-overlay/`), DVR modal (`dvr-modal/`), gif record pill (`gif-record-pill.tsx`), cast icon, copy link, draw canvas + pen cursor (Together rooms), chat overlay, content advisory toast, foreign notice (watch-party), duration mismatch chip, buffering indicator, loader layers.
- Chrome auto-hide: playing 1800ms / paused 4500ms / resume 1000ms (`player-utils.ts:21-23`).
- **HUD editing**: no drag-to-rearrange HUD editor found in the player components (the `editMode` hits in `detail.tsx`/`home.tsx`/`discover.tsx` are catalog/home-screen customization, NOT player HUD). HUD layout is instead configurable via settings: corners for avatars/chat/episodes (`use-chrome-config.ts`), `playerVolumeHud` + position, `playerMenuBlack`, `playerTitleScale/SeriesFirst`. (FACT: no HUD drag editor; INFERENCE: HUD "editing" parity = these settings + chrome theme.)
- TV-style keyboard navigation option (`playerTvNavigation`, focus-first nav).
- Esc behavior: exits fullscreen first if `playerEscExitsFullscreen`; leave confirm modal if `playerConfirmLeave` (default true) with remember option (`leave-confirm.ts`, `request-player-close.ts`, `leave-confirm-modal.tsx`).

### 1.9 Statistics (`stats-overlay.tsx`)
Rows: engine, resolution (dwidth×dheight), frame rate (`estimated-vf-fps` fallback `container-fps`), video/audio codec, hwdec current, video/audio bitrate, dropped frames (decode/vo), cache buffering %, audio track, subtitle track, speed, volume. Toggled by `playerStats` hotkey (default I).

### 1.10 Quality / buffer info
- Quality profiles (`mpv-tuning.ts:3-27`): `performance` (bilinear scale/cscale/dscale, dither off, deband off, vd-lavc-fast, no interpolation, no hdr-compute-peak), `quality` (ewa_lanczossharp, mitchell dscale, deband 2 iters, correct/linear downscaling, sigmoid upscaling, hdr-compute-peak), `balanced` (empty = mpv defaults).
- Buffer boost (`mpvBufferBoost`, default off): cache-secs 600, demuxer-max-bytes 1GiB, readahead 600s, cache-pause-initial, cache-pause-wait 10.
- Always-on (mpv.rs): non-live cache-secs 300, demuxer-max-bytes 512MiB, back 64MiB, readahead 300s, cache-on-disk in app_cache_dir/mpv-cache, network-timeout 600, reconnect opts, stream-buffer-size 32MiB; live: cache-secs 30, 64MiB/16MiB demux, readahead 20s, network-timeout 60, reconnect_delay_max 5, buffer 16MiB.
- Buffering state: `paused-for-cache` (→ `snap.buffering`), `demuxer-cache-duration` (→ `bufferedSec`), `cache-buffering-state` in stats. Seek-bar renders buffered range. P2P engines additionally expose downloaded fraction (`playback-clock.ts`, `resolvePlaybackDownloadedFraction`).
- Resolution label helper `realQualityLabel` (4K/1440p/1080p/720p/480p/SD) — `resolution-label.ts`.
- `duration-mismatch-chip.tsx` warns when media duration diverges from expected runtime by `DURATION_MISMATCH_S = 4`.

### 1.11 PiP
- mpv engine: two modes. (a) `pip.rs` opens a separate 560×360 always-on-top `harbor-pip` webview window that re-uses the same mpv (session {url, startAtSec, playing, volume, muted, title, subtitle, subtitles}) and publishes exit state back to main (`pip://closed` → position/playing). (b) `window_pip_enter/exit` shrinks the MAIN window to 480×320 bottom-right always-on-top and restores it on exit (macOS extra re-assert loop for window level, `pip_mac.rs`).
- html5 engine: Document PiP (`documentPictureInPicture`) with a custom control chrome (play/pause, ±30s, mute, volume, progress, exit; keyboard space/arrows), falling back to native `requestPictureInPicture()`; known-broken latch `DOCUMENT_PIP_KNOWN_BROKEN`. (`src/lib/player/html5/pip.ts`, `bridge.ts:657-752`.)
- `mpv_on_pip_changed` toggles mpv `ontop` (own-window mode).

### 1.12 Live / DVR / channels
- Live (IPTV): html5 default; mpegts.js or hls.js with live config (`liveDurationInfinity`, `backBufferLength:30`); DVR modal (record via `dvr.rs`, schedule, active list); EPG guide overlay; channel prev/next hotkey; live channel error state; live picture EQ; `stream-loading-bar`; live reconnection ladder (§1.3).

### 1.13 Sleep timer (`use-sleep-timer.ts`)
Modes: off / N minutes (15/30/45/60/120/180/240/360 — pauses at firesAt) / end of episode / end of next episode (remaining counter; pauses after). Toggled from transport + hotkey.

### 1.14 Power/energy (`src-tauri/src/power.rs`)
`power_inhibit(on)`: macOS `NSProcessInfo beginActivityWithOptions` (idle display + system sleep disabled); Linux xdg-desktop-portal Inhibit (suspend+idle) with org.freedesktop.ScreenSaver fallback; Windows no-op.

### 1.15 Cast / remote / together (adjacent to player, relevant for parity)
- Cast: `cast.rs`, `cast_hls.rs`, `cast_server.rs`, `cast_subs.rs`, DLNA, Roku, AirPlay, Chromecast via local HTTP server; stream proxy registers cast sessions on LAN-reachable IP; subtitle burn-in filters (`cast_subs::burn_filter`).
- Web remote: `web_server.rs` serves bundled UI on `0.0.0.0:11471` with WS control channel (`/api/remote`) — phone remote.
- Together rooms: host/guest sync, draw mode, chat, presence (`use-room-sync.ts`, `room-layer`), watch sync thresholds in `player-utils.ts` (SYNC_DRIFT_TOLERANCE_S 0.6 etc.).
- Song ID: WASAPI loopback capture 3-15s → WAV → AudD API (`song_id.rs`), Windows only.
- Trailer playback: yt-dlp sidecar downloads (360p/720p/1080p/best format strings) to temp cache with 14-day/1.5GB sweep; played via player (`trailer.rs`).
- Multiview (see §7).
- Crash recovery: panic hook writes `panic.json`; next launch offers report (`crash_report.rs`).
- mpv log: `harbor-mpv.log` in app data dir; `mpv_export_log` copies to Downloads.
- Discord rich presence (`discord_rp.rs`), tray (`tray.rs`).

---

## 2. Exact mpv option set

### 2.1 Pre-init (before playback start), `apply_pre_init` — `src-tauri/src/mpv.rs:320-460`
```
title=Harbor
audio-client-name=Harbor
terminal=no
msg-level=all=warn,vo=v,d3d11=v,gpu=v,win32=v
user-agent=VLC/3.0.20 LibVLC/3.0.20   (or source header UA)
http-header-fields=<k: v, ...>        (from src.headers)
hwdec:  mac-embed=videotoolbox-copy | linux=auto-safe | windows=auto (d3d11va if rtxHdr) | else auto
force-window:  mac-embed=no | linux=yes (embed: no) | windows/other=immediate
video-timing-offset=0                 (mac/linux embed only)
input-default-bindings=no
input-media-keys=no
input-cursor=no
osc=no (best-effort)                  osd-level=0
cursor-autohide=200
volume-max=600
background-color=#000000               background=color
media-controls=yes
wid=<hwnd> (windows embed)
d3d11-flip=no (only when d3d11Flip && hdrToSdr on windows embed)
ontop=yes / border=no (own-window mode)
start=<seconds> (when startAtSec>0)
```
HDR-to-SDR block (when `hdr_to_sdr` && !rtx_hdr):
```
tone-mapping=spline
gamut-mapping-mode=perceptual
hdr-compute-peak=yes
hdr-contrast-recovery=0.30
hdr-peak-percentile=99.995
dither-depth=auto
target-trc=bt.1886
target-prim=bt.709
target-colorspace-hint=yes (win/mac)
```
Else (passthrough): `target-colorspace-hint=yes` (win/mac), `gpu-api=d3d11` when embedded on Windows.
Anime4K: `glsl-shaders=<paths joined by ';' (win) or ':'>`.

### 2.2 Post-init — `mpv_start` (`src-tauri/src/mpv.rs:489-779`)
```
vo=gpu-next,   (own-window)   |   vo=libmpv (mac/linux embed)
log-file=<appdata>/harbor-mpv.log        mpv log level: warn
live:   cache=yes cache-secs=30 cache-pause=yes cache-pause-initial=no
        demuxer-max-bytes=64MiB demuxer-max-back-bytes=16MiB demuxer-readahead-secs=20
        network-timeout=60 stream-lavf-o=reconnect=1,reconnect_streamed=1,reconnect_delay_max=5,reconnect_on_network_error=1
        stream-buffer-size=16MiB
        scale/dscale/cscale=bilinear dither=no deband=no correct-downscaling=no
        linear-downscaling=no sigmoid-upscaling=no hdr-compute-peak=no interpolation=no
non-live: cache=yes cache-secs=300 cache-pause=yes
        demuxer-max-bytes=512MiB demuxer-max-back-bytes=64MiB demuxer-readahead-secs=300
        cache-dir=<cache>/mpv-cache cache-on-disk=yes
        network-timeout=600 stream-lavf-o=reconnect=1,reconnect_streamed=1,reconnect_delay_max=10,reconnect_on_network_error=1
        stream-buffer-size=32MiB
embed: sub-visibility=no secondary-sub-visibility=no   (UI renders subs itself in embed mode)
sub-fonts-dir=<app fonts dir>  sub-font-provider=auto  sub-font=Noto Sans JP  embeddedfonts=yes
start=<s> on loadfile via "start=" load option
```
Initial subs: `sub-add <url> auto` per subtitle.
Extra options: user lines applied verbatim as properties (skip comments; `--` prefix stripped; `key value` or `key=value`).

### 2.3 Observed properties (`OBSERVED_PROPS`, `mpv.rs:162-181`)
`time-pos, duration, pause, eof-reached, track-list, volume, mute, chapter-list, sub-delay, audio-delay, sub-text, sub-start, af, dwidth, dheight, video-params/gamma, demuxer-cache-duration, paused-for-cache` — forwarded as `mpv://event` property-change payloads (rate-limited: time-pos skipped if <200ms since last).

### 2.4 Frontend property set (runtime controls, `src/lib/player/mpv.ts` + `mpv-forward.ts`)
`pause, volume(0-600), mute, speed, aid, sid ("no" to disable), sub-visibility, sub-delay, audio-delay, panscan(0-1), video-zoom, video-aspect-override, keepaspect, glsl-shaders, af (dynaudnorm=f=500:g=31:p=0.9:m=4 + profile lavfi + alimiter=limit=0.97), audio-device, force-media-title, ab-loop-a/ab-loop-b ("no"), fullscreen, screenshot-format/png-compression/sw, user-agent, http-header-fields, ontop, target-colorspace-hint-mode (rtx-hdr), tone-mapping et al. (setHdrToSdr), target-peak reassert (Windows HDR), target-trc/prim/peak + icc-profile-auto (macOS EDR), video-sync=display-resample + interpolation=yes + tscale=oversample (motion interp).`
Sub style properties from `sub-style.ts:50-68`: `sub-font-size=32, sub-font, sub-scale(0.4-4), sub-color #AARRGGBB, sub-border-color, sub-border-size, sub-back-color, sub-shadow-color, sub-shadow-offset(1.4 shadow style), sub-margin-y, sub-align-x, sub-ass-override(no|yes|force|scale|strip), sub-ass-force-margins, sub-use-margins, sub-spacing, sub-bold, sub-pos`.
Blocked properties/commands (security, `mpv.rs:1045-1067`): commands allow-listed to `af, vf, seek, stop, frame-step, frame-back-step, loadfile`; properties starting `script, input-, load-scripts, ytdl-raw, screenshot-directory, screenshot-template, sub-add` are refused. User `mpvExtraOptions` is additionally screened by `validateMpvOptions` (RISKY: scripts?, load-script, input-ipc-server, input-conf, input-cmdlist, ytdl-raw-options) — `mpv-tuning.ts:67-89`.

### 2.5 Enhancements options
- **Anime4K** (`anime4k-modes.ts`): modes A/B/C/AA/BB/CA; tiers hq(VL)/fast(M); shader chains e.g. A = Clamp_Highlights → Restore_CNN → Upscale_CNN_x2 → AutoDownscalePre_x2/x4 → Upscale_CNN_x2_M. Shaders downloaded from `https://raw.githubusercontent.com/bloc97/Anime4K/master/glsl/...` into app-data `anime4k/` (`anime4k.rs`). Runtime toggle via `glsl-shaders`; indicator chip; `playerAnime4kOverride` auto chooses mode by source resolution (see `use-anime4k.ts`).
- **SVP** (`svp-policy.ts`, `svp.rs`, `mpv-tuning.ts:52-58`): active when `playerSvp` && vpy path set && scope matches (all/anime/non-anime; anime = kitsu/mal/anilist/anidb id or genre anime/animation). mpv lines: `vf=@harbor-svp:vapoursynth=[<vpy>]`, `hwdec=auto-copy`, `hr-seek-framedrop=no`. Failure handling: mpv log lines about vapoursynth failure → `vf remove @harbor-svp` + `harbor:svp-failed` event (`mpv.ts:127-135,142-153`). Status probe checks SVP root (SVPManager.exe / SVPManager), VSScript.dll, svpflow plugins, mpv vapoursynth support (`supports_vapoursynth_filter`); Linux: `vapoursynth config` setup, Flatpak blocked; Windows: preloads VSScript chain + CRT env. `svpEnsureRunning` (lib/svp) launches SVPManager.
- **RTX HDR** (`rtx-hdr.ts`): Windows only; `vf add @harbor-rtx-hdr:d3d11vpp=nvidia-true-hdr`; requires `target-colorspace-hint-mode=source` (snapshot+restore); blocked when hdrToSdr on or SVP active; only for SDR sources (gamma not pq/hlg, primaries not bt.2020, per `video-dec-params/gamma|primaries`) — `rtx-hdr-policy.ts`. Reset per session key; hotkey toggle.
- **Motion interpolation** (`motion-interp.ts`): on → `video-sync=display-resample, interpolation=yes, tscale=oversample`; off → `interpolation=no, video-sync=audio`.
- **HDR stage** (`hdr_overlay.rs`, `hdr-stage-bridge.tsx`): a transparent always-on-top `harbor-hdr-overlay` webview is placed ABOVE the embedded mpv child HWND on Windows when content is HDR (so UI pixels stay HDR-correct); mpv child z-order toggled `HWND_TOP`/`HWND_BOTTOM` and `WS_EX_TRANSPARENT` removed/added (`mpv.rs:2275-2464`); `playerHdrStage` auto/off/always. `display_hdr_active` queries DXGI output color space (G2084/P2020); `reassert_hdr_colorspace` pokes `target-peak=10000→auto` 250ms after gamma change.

---

## 3. HTML5 fallback behavior and triggers

Engine for a source is decided in `use-player-bridge.ts` + `pickBridge` (`player-utils.ts:53-87`):

1. `playerEngine` setting:
   - `html5` → always html5.
   - `mpv` → mpv; if `probeMpv()` (creates a test libmpv context, reads `mpv-version`) fails → html5 fallback with warning.
   - `auto` (default): desktop (Tauri) or `notWebReady` → mpv if probe ok, else html5; web/browser context → html5.
2. Live-like sources (`iptv:` id, or meta type not in movie/series/anime) and NOT `notWebReady` → html5 regardless (live uses hls.js/mpegts.js for resilience).
3. **Post-error auto-fallback**: when currently on html5 with `playerEngine=auto`, if snapshot hits `errorCode` `decode`/`codec` or `noAudio` (webkitAudioDecodedByteCount==0 with video frames present), and mpv probe succeeds, engine switches to mpv (one-time per session).
4. Auto-retry ladder can force web-agnostic paths (transcode → `notWebReady:true` → mpv preferred).
5. mpv embed vs own window is orthogonal (setting `playerMpvEmbed`, HDR-opaque-window exception).
6. HTML5 capabilities: `pictureInPicture` (native or Document PiP), `airplay` (WebKitPlaybackTargetAvailabilityEvent), no chromecast, `hdrPassthrough:false`, `hardwareDecode:true` (browser-managed).
7. html5 source plumbing: hls.js when URL matches `.m3u8`/`m3u8`/`/playlist/` and supported (live config when notWebReady or isLive: `enableWorker, lowLatencyMode:false, liveDurationInfinity:true, backBufferLength:30`); mpegts.js for `.ts` or notWebReady non-standard extensions (`isLive:true, cors:true, liveBufferLatencyChasing`); else native `video.src`. Audio-track switching via `hls.audioTracks` or `video.audioTracks`; no-audio probe via webkit decoded byte counts. Autoplay unlock: play() with mute-unmute retry ladder. Subtitle cues parsed in JS (`src/lib/subtitles/parser`) and ticked via rAF against `currentTime - subDelay`. MediaSession handlers bound. PiP/fullscreen/screenshot as in §1.

---

## 4. Trickplay / thumbnail generation & storage (`src-tauri/src/thumbs.rs`, `src/lib/trickplay.ts`, `thumb-preview.tsx`)

- On-demand "shadow mpv" scheme: one hidden mpv process per session, launched with `--input-ipc-server=<named pipe/socket harbor-thumbs-<uuid>>`, `--no-config --no-audio --no-sub --vo=null --pause=yes --keep-open=yes --idle=yes --load-scripts=no --ytdl=no --cache=yes --demuxer-max-bytes=32MiB --vf=scale=240:-2 --screenshot-format=jpg --screenshot-jpeg-quality=72 --screenshot-tag-colorspace=no --hr-seek=no -- <url>` (with `--` terminator to stop option injection).
- Bucket size: `BUCKET_SECONDS = 2.0`; request for time T → bucket = round(T/2) → target = bucket*2s.
- Generation: send `seek <target> absolute keyframes` over IPC; wait for `playback-restart` event (Notify, ≤4s); send `screenshot-to-file <cache-dir>/<bucket>.jpg video` with request_id; wait for matching response (≤12s); read file, delete it, return `data:image/jpeg;base64,...`.
- **Storage format**: in-memory LRU only — `ThumbCache` max 160 entries / 48MiB, keyed by bucket, evicts least-recently-used; plus a React-side `Map<bucket, dataUri>` (`lib/trickplay.ts`) with nearest-bucket lookup within ±30 buckets. Session cache dir `%TEMP%/harbor-thumbs/<session>` (deleted on stop). No persistent on-disk thumbnails.
- Flow: `thumbs_set_url(url)` (clears cache, new session, kills previous shadow) → `thumbs_spawn_eager` (spawns shadow immediately for VOD) → `thumbs_get(timeSec)` per hover; worker serializes requests; stale sessions dropped. `thumbs_stop` on unmount.
- UI (`thumb-preview.tsx`): 192×108 card, 2s buckets, poll/retry up to 24×400ms, "approximate" nearest thumb at 60% opacity, skip-segment labels (OP/ED/Recap/Ad) overlaid. For bundled-engine (torrent) URLs, `bufferedOnly` state signals preview availability only inside buffered range.

---

## 5. Subtitle handling

### 5.1 Formats & loading
- Formats: SRT, VTT, ASS/SSA (and image subs PGS/HDMV/DVDSUB/VOBSUB/DVB/XSUB detected for menu handling via `sub-format.ts`; image subs are mpv-side only). Detection of ASS by codec/title/`.ass|.ssa` regex, image subs by codec string (`sub-format.ts`).
- Remote subs are downloaded in Rust (`sub_download`, `mpv.rs:2020-2074`): reqwest with 15s timeout, gzip auto, UA spoof, then `prepare_subtitle_download`: encoding normalization (UTF-8 BOM strip; UTF-16 LE BOM → UTF-8; legacy encodings via encoding_rs: hint, else windows-1256 for Arabic, else windows-1252), extension resolution (hint → content sniff `[Script Info]`/`WEBVTT` → URL/extension → default srt); written to `%TEMP%/harbor-subs/<uuid>.<ext>`; returned path is `sub-add`ed with title/lang.
- On-disk (local/imported) subs converted via `convertFileSrc`; `imported-subs.ts` tracks imported titles per session.
- Track list labels: `title|lang · CODEC · channels · Forced · SDH · External` (`mpv.ts:172-228`).
- mpv-side add: `mpv_sub_add {url, lang, title, select}` → `sub-add <url> select|auto <title> <lang>`.
- html5-side: JS parser (`src/lib/subtitles/parser.ts` `fetchAndParse`/`findActiveCue`) supports SRT/VTT/ASS (text); cues ticked per rAF; delay applied as `currentTime - subDelaySec`.
- Track autoload + provider search (`use-track-autoload.ts`, `subtitle-menu/search-section.tsx`): providers wyzie / opensubtitles / jimaku / addons (settings `subProvidersEnabled`); `use-sub-drop.ts` handles drag-drop of subtitle files; embedded-sub extraction via ffmpeg `-map 0:s:N -f srt` (`sub_extract.rs`, 90s timeout, 4MiB cap).

### 5.2 Dual subtitles
- FACT: mpv's `secondary-sub-visibility` is set to `no` when embedded, and no code sets `secondary-sid` (grep for secondary-sid/secondary sub across src returned zero matches). The dual-subtitle feature therefore does not exist in the inspected build; only single-track rendering (UI renders `sub-text` itself in embed mode; mpv renders otherwise).

### 5.3 Styling (`sub-style.ts`, `sub-presets.ts`, `sub-style-bar/`)
- All styling via mpv properties (see §2.4). Style presets (English/Foreign/Arabic seeds + user presets, max 12, localStorage `harbor.sub.presets.v1`). Style bar with advanced menu (alignment, margins, opacity, box, line spacing, bold, ASS override) and looks cluster. Arabic preset forces ASS override + Noto Sans Arabic. `applySubStyle` repositions via `sub-pos` unless native ASS margins requested.

### 5.4 Delay & sync
- Manual: `sub-delay` property ±0.1s steps (Shift 0.05s); `sub-sync-bar.tsx` provides the UI (press up/down while paused, per-bar store `sub-sync.ts`).
- **Auto-sync** (opt-in `subtitleAutoSync`, default false) `use-auto-sync.ts` + Rust `subsync/*`:
  - Gate: engine must be mpv, duration ≥ 60s, ≥4 cues, external selected track, not loopback, not debrid (infoHash non-empty → skip), ffmpeg present.
  - `extract.rs::speech_intervals`: ffmpeg decodes audio windows (silencedetect noise=-30dB d=0.35, bandpass 200-3000Hz mono) and inverts silence → speech intervals. Windows: dur<15min → [5%, 90%]; else early [180,600] + late [dur-720, 600].
  - `correlate.rs::solve`: rasterize both sequences at 100Hz grid; FFT cross-correlation over lags ±60s; try ratios [1.0, 1.25, 0.8, 1.0427, 1.00092, 1.04167] + inverses (PAL/NTSC drift); pick best by NCC; accept if NCC ≥ conf_min (0.55), z ≥ 6, dominance ≥ 1.3, |offset| ≤ 60s. Returns {offsetSec, ratio, confidence}.
  - Apply: shift(t) = offset + (ratio-1)·t; re-serialize cues to SRT/VTT; save to `%TEMP%/harbor-subs/autosync-*.srt|vtt` via `save_text_file`; `addSubtitle(..., "Synced (SRT)", select)`; reset sub-delay.
  - `moviehash.rs`: classic 64KiB head+tail hash (local file or HTTP Range 0-65535 / size-65536..size-1) — exposed for external subtitle-provider matching.
- Cast burn-in: `cast_subs::burn_filter(path, forceStyle)` subtitles filter for casting; transcode `burn_sub` option.

---

## 6. Intro/outro providers (skip-intro)

`src/lib/skip-intro/` — `types.ts`: `SkipKind = intro|outro|recap|ad`; `SkipSource = aniskip|introdb|chapters|adcorpus`.

### 6.1 AniSkip (`aniskip.ts`)
- API: `GET https://api.aniskip.com/v2/skip-times/{malId}/{episode}?types=op&types=ed&types=mixed-op&types=mixed-ed&types=recap&episodeLength=<sec>`
- Response: `{found, results:[{interval:{startTime,endTime}, skipType}]}`; `ed|mixed-ed` → outro, `recap` → recap, else intro. In-memory cache keyed `malId:episode:len` + inflight dedupe.
- ID mapping: Kitsu id → MAL via localStorage cache → SIMKL local cache (`kitsuToSimkl` + `malToSimkl`) → `GET https://kitsu.io/api/edge/anime/{kitsuId}/mappings` (externalSite `myanimelist/anime`).

### 6.2 TheIntroDB (`theintrodb.ts`)
- API: `GET https://api.theintrodb.org/v2/media?tmdb_id=<id>` or `?imdb_id=tt...` and optional `season`/`episode`.
- Response spans in ms: `intro`, `recap`, `credits`, `preview` (credits+preview → outro; missing end_ms → duration). In-memory cache + inflight dedupe.

### 6.3 Chapters (`chapters.ts`)
- Classifies mpv chapter titles by regex: recap ("recap|previously"), intro ("opening|op|intro|opening credits|theme song"), outro ("ending|ed|outro|end credits|closing credits|credits"); span = chapter start → next chapter start (or duration, or start+90s).

### 6.4 Ad corpus (`adcorpus.ts`)
- `GET https://harbor.site/updates/ad-segments.json` — `{payload, sig}` Ed25519-signed (embedded pubkey `yszDA2+...=`), verified via WebCrypto before parse. Entries: `{content, source, ranges:[{start,end}]}`; matched by `content` = IMDB id (tt...) or meta id, `source` = `ih_<infohash>_<fileIdx>` | `rg_<group>_<size>_<title>` | `u_<host+path>` (fingerprint.ts). Segments kind `ad`.

### 6.5 Merge semantics (`index.ts`)
- Priority merge `[adSegments, aniSkip, introDb, chapters]`, first-wins on overlap; sorted; length 2-360s; end clamped to duration; outros only after `MIN_OUTRO_START_FRACTION = 0.5`; `prefetchSegments` warms caches for adjacent episodes.

---

## 7. Multiview mode (`src-tauri/src/multiview.rs`, `src/views/multiview.tsx`)

- Windows-only (returns "Multiview is currently Windows-only" elsewhere).
- Up to `MAX_SLOTS = 4` simultaneous streams. Each slot = separate child `mpv.exe` process (external binary, same locator as DVR) embedded into the main window (`--wid=<main hwnd> --title=HARBOR_MV_SLOT_<n>`), positioned via CSS→physical geometry mapping (`css_to_physical`) with round-corner window regions (18px) and `HWND_TOP`; hidden by moving to (-30000,0).
- Each mpv: `--input-ipc-server=\\.\pipe\harbor-mv-<slot>-<pid>`, `--idle --keep-open --no-osc --no-osd-bar --osd-level=0 --input-default-bindings=no --input-media-keys=no --no-input-cursor --cursor-autohide=no --no-config --cache=yes --cache-pause=no --cache-pause-initial=no --cache-secs=20 --demuxer-readahead-secs=30 --network-timeout=60 --stream-lavf-o=reconnect... --vd-lavc-threads=2 --volume=100 --mute=yes --user-agent=...`. IPC JSON is serde-serialized (newline-injection hardening); oversized IPC messages dropped; events `end-file`(error|eof|network|unknown) → `multiview-slot-error`, `file-loaded|playback-restart` → `multiview-slot-playing`.
- Audio: exactly one slot unmuted — `multiview_audio_focus(focus)` mutes all others (`-1` mutes all). `multiview_open` replaces slot URL in-place if the slot already exists (no respawn); `multiview_prespawn` pre-warms idle slots; other slots get a `video-zoom 0` redraw poke after a new load; `multiview_stop_all`/`close`/`visibility` manage lifecycle; orphan mpv processes for a slot are killed (pid + window title matching).
- Frontend `views/multiview.tsx` shows a picker grid to choose which streams occupy the slots; the main player continues in the remaining region (CSS geometry drives slot rects).

---

## 8. Stream proxy & transcode (`src-tauri/src/stream_proxy.rs`, `src-tauri/src/transcode.rs`)

### 8.1 Proxy
- axum server bound to `127.0.0.1:0` (ephemeral port). Routes: `/s/{id}` (single stream, GET/HEAD), `/p/{id}/{*path}` (HLS playlist + segments), `/health`.
- `register`: UUID session {url, headers, transcode flag, profile, burn_sub}. HLS URL (`.m3u8` last segment) → playlist session served at `/p/{id}/<last_seg>`; else `/s/{id}`.
- `register_cast`: resolves a LAN-reachable IP (`reachable_ip_for(target_host)` else `lan_ip()`); if transcode → registers an HLS transcode session (`cast_hls`) served at `/cast/hls/{id}/master.m3u8`; HLS fallback to direct `/s/` transcode; else playlist/direct session on the LAN URL.
- Forwarding: streams upstream via reqwest with header forward list (range, accept, user-agent, referer, origin, if-range, if-none-match, if-modified-since) unless session headers override; session headers injected (accept-encoding excluded); response headers forwarded (content-type/length/range/accept-ranges/etag/last-modified/cache-control); CORS `*` + headers; `accept-ranges: bytes` added; octet-stream content-type overridden by URL extension guess; `.m3u8` bodies get `cache-control: no-cache`, forced `application/x-mpegURL`, and `CODECS="avc1.640029,mp4a.40.2"` injected into `#EXT-X-STREAM-INF` lines lacking it.
- GC: sessions > 3h evicted; HLS idle 5min; `proxy_gc_idle` command; shutdown stops HLS sessions. Frontend wrapper `src/lib/stream-proxy.ts` (`registerStreamProxy`/`unregisterStreamProxy`).
- Consumers: auto-retry ladder (steps 4/5), stream switcher (headers), debrid failover, cast, live.

### 8.2 Transcode (`handle_transcode`)
- Per request: ffprobe codec probe (8M analyzeduration/probesize, 12s timeout, `-i` flag-safe), then ffmpeg → MPEG-TS pipe:
  - Common: `-hide_banner -loglevel error -fflags +genpts+nobuffer+discardcorrupt -flags low_delay -reconnect 1 -reconnect_streamed 1 -reconnect_on_network_error 1 -reconnect_on_http_error 5xx,4xx -reconnect_delay_max 8 -analyzeduration 8M -probesize 8M -i <url> -map 0:v? -map 0:a?`, UA + `-headers` blob.
  - Video: re-encode (`profile.force_h264 || codec != h264 || burn_sub`) → `libx264 -preset veryfast -crf 22 -profile:v high -level 4.1 -pix_fmt yuv420p -g 60 -sc_threshold 0`, scale filter `scale='if(gt(ih,H),min(W,iw),iw)':'if(gt(ih,H),H,ih)':force_original_aspect_ratio=decrease,scale=trunc(iw/2)*2:trunc(ih/2)*2` (H→W: 720→1280, 2160→3840, else 1920), optional maxrate/bufsize (6000k default), optional `ass=...` burn-in filter appended; else `-c:v copy -bsf:v h264_mp4toannexb`.
  - Audio: re-encode (`force_aac || != aac`) → `aac -b:a 192k` (`-ac 2` if force_stereo) else `copy`.
  - Output: `-f mpegts -mpegts_flags +resend_headers+initial_discontinuity -mpegts_copyts 1 pipe:1`; response headers include DLNA `transferMode.dlna.org: Streaming` and `contentFeatures.dlna.org: DLNA.ORG_PN=MPEG_TS;...` for DLNA receivers. Client disconnect kills ffmpeg (`relay_child_stdout` select on `body_tx.closed()`); stderr drained to log.
- `TranscodeProfile` default: max_height 1080, force_h264, force_aac, force_stereo, max_video_kbps 6000. ffmpeg/ffprobe locator (`locate_ffmpeg`) searches bundled binaries, PATH, common install dirs (Windows/brew/Flatpak-ish candidates).

---

## 9. FACT vs INFERENCE

### FACT (directly observed in code)
- Engine selection rules, mpv property allow/block lists, exact option strings in §2 (all copied from source).
- Watched threshold 0.85; resume min 5s; stub cap 150s; auto-next end conditions; MAX_AUTORETRY_ATTEMPTS 5; stall/freeze timeouts (75s/18s/6s/18s/9s/50s/20s/75s) — all constants in `player-utils.ts` / hooks.
- Skip-provider API endpoints, parameters, response shapes (§6).
- Thumb generation pipeline: 2s buckets, 240px width, jpg q72, LRU 160 entries/48MiB, no persistent storage (§4).
- Multiview Windows-only, ≤4 slots, single audio focus, external mpv.exe child processes (§7).
- Proxy/transcode routes, header handling, CODECS injection, ffmpeg command line, DLNA headers (§8).
- Dual/subtitles-secondary: **not implemented** — `secondary-sid` never set; `secondary-sub-visibility` is only forced off in embed mode.
- Auto-sync algorithm details (windows, ratios, thresholds, apply math) (§5.4).
- Sub encoding normalization incl. windows-1256 Arabic default and UTF-16 handling (unit tests confirm).
- HDR-to-SDR property set, RTX HDR filter label `@harbor-rtx-hdr:d3d11vpp=nvidia-true-hdr`, SVP filter label `@harbor-svp`, macOS EDR handling, HDR overlay stage mechanics.
- Sleep timer presets; power-inhibit implementations per platform; PiP two-mode design; crash report format; web remote port 11471.

### INFERENCE (behavior implied but not directly verifiable from static inspection)
- Auto-skip (skipping segments without pressing the pill) appears NOT to exist — the pill always requires a click; no timer-based auto-skip code was found. The "countdown" is for Next-Episode, not auto-skip.
- "HUD editing" parity: no drag-to-reposition HUD editor exists; the closest equivalents are the chrome theme, corner-position settings, volume-HUD position, title scale, and menu-black mode.
- The mpv `vo=gpu-next` + hwdec combos per platform are the only render paths; behavior on specific GPU/driver combos (e.g. d3d11va fallbacks) is delegated to mpv itself.
- Audio profile AF chains are applied in the order normalize → profile → limiter (from `applyAudioFilters`), and `af` observed property only reports dynaudnorm presence — exact effective chain may be reordered by mpv.
- Skip-segment `activeSegment` uses a 0.75s tail margin; exact skip seek target is the segment end (inferred from `onSkip` usage in `skip-pill-container.tsx`, not re-verified line-by-line).
- html5 ASS styling is text-only parsing; ASS positioning/styling fidelity is limited to what the JS parser produces (parser internals not fully inspected here).
- The "auto" Anime4K override resolution logic (`use-anime4k.ts` `anime4kShadersFor`) was referenced but not read line-by-line; chain files listed in `anime4k-modes.ts` are fact.
- Priority of retry ladder steps follows the effect ordering in `use-auto-retry.ts`; races between simultaneous error effects are guarded by per-step refs (fact), but the exact interleaving under rapid multi-error conditions is untested.
