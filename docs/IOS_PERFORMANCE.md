# IOS Performance

> Budgets and measurement plan (spec §80–81). Measure first, then optimize — never optimize blind.

## Budgets (targets — validated on-device, not guessed)

| Metric | Budget |
|---|---|
| Cold startup → Home ready | < 2.5 s (A17) |
| Home first render (cached) | < 800 ms |
| Rail scroll | 60 fps, no dropped frames at 4 rails × 12 cards |
| Image load (poster) | memory-capped decode, async, cancellable |
| Search (debounced) | results < 400 ms p50 (cached), cancel on keystroke |
| Detail open → render | < 1 s with cached metadata |
| Stream discovery (5 addons) | parallel, partial-results progressive, < 8 s p90 |
| Playback start (https direct) | < 2.5 s |
| Stream switch | < 3 s |
| Live TV channel zap | < 1.5 s (after tune) |
| EPG day render | < 500 ms |
| Memory — browsing | < 300 MB steady-state |
| Memory — 1080p playback | < 500 MB |
| Memory — 4K/HDR | device-class aware (cap on older devices) |
| Battery — 1080p playback | ~Harbor-desktop-class (no background P2P by design) |

## Instrumentation

- Signposts (`os_signpost`) around: startup, home render, detail, stream discovery, playback start, EPG, multiview.
- MetricKit for field memory/CPU/battery.
- In-app diagnostics screen: timings + memory pressure log (sanitized).

## Memory discipline (spec §81)

- Every cache bounded (count + bytes): images, metadata, addon responses, EPG, trickplay.
- `didReceiveMemoryWarning` → drop non-essential caches, never crash.
- Multiview: decode-capability probe; degrade tile count (A17 vs older).
- No catastrophic growth on: large EPG (days × channels), Theme Studio live preview, long playback sessions.

## Known expensive paths

| Path | Why expensive | Mitigation |
|---|---|---|
| Trickplay generation | thumbnail extraction per file | background, low priority, bounded cache |
| EPG ingest (huge XMLTV) | XML parsing | streaming SAX-style parser, incremental store |
| Addon fan-out | N addons × M requests | concurrency cap + timeout + partial results |
| ASS rendering in libmpv | complex scripts | mpv libass — accept, tune `sub-ass-override` |

## CI perf smoke

- Simulator unit tests include a startup-timing smoke (loose bound) to catch pathological regressions early.
- Real budgets verified on-device only; CI numbers are indicative.
