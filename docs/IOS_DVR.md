# IOS DVR

> Honest DVR plan (spec §55: implement genuine functionality where iOS permits; no fake DVR). Harbor's own DVR is shallow — this is verified by `docs/audit/live-tv-dvr.md` §4.

## What Harbor DVR actually is (FACT)

- Manual-start, **live-only**, fixed-duration recording via an external headless `mpv --stream-record` process.
- Progress/watchdog loops (2s), in-memory session map, kill-on-finalize.
- **No scheduling, no recording library, no persistence across restarts, no disk-space checks, no in-app playback, no collision handling, no retry.**
- UI: record modal from live player (duration: current program / current+next / next / custom 5–720min), recording pill in player chrome, "Show in folder".

## Parity decision

**We reproduce the Harbor surface exactly, and implement the strongest native mechanism for it:**

| Harbor | iOS |
|---|---|
| external mpv `--stream-record` (spawns a process — impossible on iOS) | **in-app recording**: AVFoundation `AVAssetWriter` for the AVPlayer backend; MPVKit `stream-record` option for the mpv backend (same mpv mechanism, in-process!) |
| `.ts` output, fixed dir "Harbor DVR" | same container preference (`.ts` via AVAssetWriter needs muxing care; fallback `.mp4` documented), app Documents/Harbor DVR (Files-app visible) |
| in-memory sessions, lost on restart | **better**: persistent recording index (safe divergence, documented — Harbor's volatility is a defect, not a feature) |
| duration presets incl. EPG-derived (current/next/custom 5–720) | identical presets |
| no playback of recordings | parity v1: keep "no in-app playback" OR exceed via local-media player (documented decision below) |

## iOS lifecycle reality (documented limitation, spec §55)

- Foreground recording: fully supported.
- Background recording of live network streams: **not permitted** by iOS (audio-only background via audio session; video capture of network streams isn't backgroundable). Scheduled "record the 21:00 show" while the app is closed = **impossible**.
- Result: DVR works while the app is in foreground with the screen on (including while watching another channel — subject to memory). Scheduling UI is therefore **not built** (parity: Harbor has no scheduling either).

## Recording design

- `RecordingEngine` protocol with two backends: `AVPlayerRecorder` (AVAssetWriter from the playback item) and `MPVRecorder` (mpv `stream-record` prop — the same flag Harbor uses, in-process).
- Sessions: `{id, url, channelName, programTitle?, outputPath, startedAt, plannedDurationSec, bytesWritten, state}` — mirrored event stream (`dvr://progress|done|error` semantics) so the pill UI matches Harbor.
- Watchdog + progress ticks (2s, same as Harbor). Stop → finalize → done.
- Disk-space check before start (Harbor lacks it; iOS adds it — safe improvement, documented).
- Files: Documents/Harbor DVR, user-visible via Files app (iOS "Show in folder" equivalent = open Files bookmark).

## Status

| Item | Status |
|---|---|
| Harbor DVR surface (modal, pill, presets, progress) | PLANNED |
| AVPlayerRecorder | PLANNED (validate `.ts` muxing → likely `.mp4`) |
| MPVRecorder (`stream-record`) | PLANNED (same flag as Harbor — highest fidelity) |
| Scheduling / background recording | BLOCKED by platform (documented) |
| Recording library + in-app playback | DISCOVERED (decision: reuse local-media player — Phase 20) |
