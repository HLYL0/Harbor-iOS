# IOS Known Limitations

> Every limitation, with Harbor evidence + iOS reason + alternative + status (spec §102: no silent drops). This file is the single place where "we don't do X like Harbor" is documented.

## Blocked / restricted features

| Feature | Harbor evidence | iOS restriction | Our alternative | Status |
|---|---|---|---|---|
| Built-in torrent engine (librqbit) | `torrent_engine/*` | no background P2P sockets; battery/lifecycle | Debrid resolver path (all 5 providers); foreground-only engine not planned | BLOCKED (documented) |
| In-app transcoding (ffmpeg subprocess) | `transcode.rs` | no process spawning | libmpv/AVPlayer native codec coverage; casting without local transcode | BLOCKED (documented) |
| Local stream proxy server | `stream_proxy.rs` | lifecycle limits | retry ladder without proxy steps; header injection direct to player | NOT PORTED (documented) |
| SVP frame interpolation | `svp.rs` | external SVP dependency, no pipeline access | — (mpv's own interpolation flag remains for basic motion smoothing) | NOT APPLICABLE |
| RTX Video Super Resolution / HDR | `rtx-hdr*.rs` | NVIDIA-only | HDR-to-SDR mpv pipeline (Harbor's default) + native EDR | NOT APPLICABLE |
| Discord Rich Presence | `discord_rp.rs` | no Discord desktop IPC on iOS | Now Playing / Lock Screen (MPNowPlayingInfoCenter) | NOT APPLICABLE |
| Windows media controls | — | Windows-only | Now Playing | NOT APPLICABLE |
| Multiview on all platforms | Windows-only in Harbor (FACT) | iOS decode limits | 2 tiles + device-aware upgrade path | REWRITE (design freedom) |
| DVR background/scheduled recording | Harbor itself has NO scheduling (FACT) | iOS background rules | foreground recording, EPG-preset durations (full Harbor surface) | BLOCKED (background only) |
| Dual subtitles | **NOT in Harbor** (FACT — secondary-sid never set) | — | single track (parity) | NOT APPLICABLE |
| Player HUD drag-editor | **NOT in Harbor** (FACT — settings-based) | — | HUD via settings + chrome theme (parity) | NOT APPLICABLE |
| Auto-skip intro/outro | **NOT in Harbor** (INFERENCE — pill is manual) | — | manual skip pills (parity) | NOT APPLICABLE |
| Custom theme CSS/JS execution | Harbor runs unsandboxed `new Function` | iOS forbids privileged JS bridges | token-level theming + native chrome builder; JS never executed | BLOCKED (security) |
| EPG date navigation | **NOT in Harbor** (FACT — 8h now-window only) | — | parity: no date nav | NOT APPLICABLE |
| EPG generation/export | **NOT in Harbor** (FACT) | — | parity: M3U export only | NOT APPLICABLE |
| AirPlay receiver (server) | `airplay.rs` (desktop server) | iOS is a sender | system AirPlay routes | NATIVE EQUIVALENT |
| Chromecast sender | `cast*.rs` + vendored rust_cast | needs iOS protocol impl | P2 priority, post-player-milestone investigation | UNKNOWN → investigate |
| Web remote control server | `web_server.rs` :11471 | iOS can't serve long-lived LAN UI | not ported; watch-together covers sync use-case | NOT PORTED (documented) |

## Honest UNKNOWNs (device validation pending)

| Item | State |
|---|---|
| libmpv + system PiP | UNKNOWN — investigate AVSampleBufferDisplayLayer PiP; else AVPlayer-only PiP |
| HDR10/DV playback matrix via MPVKit on-device | UNKNOWN — needs on-device test |
| AVAssetWriter `.ts` muxing for DVR | UNKNOWN — may ship `.mp4` (documented) |
| Multiview >2 tiles on A17 | UNKNOWN |
| Chromecast protocol stability | UNKNOWN |

## Parity-relevant Harbor facts that shape us

- Harbor's RD `cacheCheck` is a stub (returns {}); AllDebrid/Premiumize/TorBox/Debrid-Link have real batch cache checks. We port that asymmetry as-is.
- Harbor stores Xtream/debrid/sync credentials in plaintext localStorage and exports them in `.harbx` — iOS diverges deliberately (Keychain, no-secret exports). Every divergence is in `IOS_SECURITY.md` + `IOS_LOCAL_FILES.md`, never silent.
- Harbor's Trakt/anilist network paths bypass its own privacy blocklist (FACT) — our wrapper enforces uniformly (safe improvement, documented).
- Harbor has 4 UI languages; Arabic missing 911 keys fall back to English (parity behavior, upstream contribution opportunity).

## Procedure

Any new limitation discovered during implementation gets a row here in the same commit. Any UNKNOWN resolved by device testing gets its state updated in the same commit.
