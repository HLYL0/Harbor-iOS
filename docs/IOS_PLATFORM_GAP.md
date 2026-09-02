# IOS Platform Gap

> Harbor desktop capability → iOS reality. Every desktop feature that cannot be copied verbatim lands here with its iOS strategy. **No silent feature drops** (spec §102): limitation + alternative + decision + status.

## Legend

| Class | Meaning |
|---|---|
| NATIVE EQUIVALENT | Apple framework replaces the desktop mechanism |
| REWRITE FOR IOS | same behavior, different implementation |
| FULL IMPL, DISTRIBUTION RESTRICTED | works technically, sideload-only |
| BLOCKED BY PLATFORM | iOS physically cannot do this |
| NOT APPLICABLE | desktop-environment feature |

## Matrix (draft — rows refined against audit reports)

| Harbor capability (source) | iOS reality | Class | Strategy |
|---|---|---|---|
| Local torrent engine — librqbit (torrent_engine/) | No long-lived P2P sockets in background; battery/app-lifecycle kills it | BLOCKED (background) | Debrid resolver path is primary (already built). Foreground-only selective-download engine possible but low value; document, don't build |
| Built-in transcoding (transcode.rs, ffmpeg subprocess) | Cannot spawn processes; no ffmpeg binary | REWRITE/ LIMITED | No in-app transcode. Player handles codecs natively via libmpv; casting transcodes don't apply |
| Stream proxy / local web server (web_server.rs, stream_proxy.rs) | Possible in-process (NWListener) but lifecycle-limited | REWRITE | Only if a feature truly needs a local URL (casting/relay); low priority |
| SVP frame interpolation (svp.rs) | Requires external SVP; no GPU pipeline access | NOT APPLICABLE | — |
| RTX Video Super Resolution (rtx-hdr) | NVIDIA-only | NOT APPLICABLE | — |
| Discord Rich Presence (discord_rp.rs) | iOS apps cannot IPC to Discord desktop | NOT APPLICABLE | Native "Now Playing" fills the gap |
| Windows media controls | Windows-only | NOT APPLICABLE | Now Playing / Lock Screen / Control Center (MPNowPlayingInfoCenter + remote commands) |
| Song identification (song_id.rs) | ShazamKit (SHSession) | NATIVE EQUIVALENT | implement when player parity reached |
| Custom AirPlay server (airplay.rs) | iOS is an AirPlay *sender* via system (AVRoutePickerView / playback routes) | NATIVE EQUIVALENT | CastingManager → AirPlay adapter = system routes |
| DLNA server (dlna.rs) | DLNA control-point possible via network protocol; server-side streaming from device impractical | PARTIAL | DMC (control point) only; document |
| Chromecast (cast.rs, rust_cast vendor) | Protocol is open; iOS can implement a DIAL/Cast sender over mDNS+TCP | REWRITE | CastingManager adapter; investigate `OpenCastSwift`-style impl vs defer |
| Roku (roku.rs) | Roku ECP is plain HTTP — fully portable | REWRITE (small) | CastingManager adapter |
| Watch Together relay (cf_relay.rs) | Cloudflare-relay signaling runs server-side; iOS is a client | NATIVE EQUIVALENT (client) | reuse protocol, iOS client + relay remains external |
| Multiview (multiview.rs) | 2–4 decoders × hardware — iPhone 15 Pro can do 2–4 tiles with decode limits | REWRITE, device-aware | 2 streams first, degrade per device class |
| DVR record to disk (dvr.rs) | No background recording of live streams; foreground recording possible; storage via sandbox | LIMITED | Foreground/scheduled-while-open recording only; honest docs (spec §55) |
| Background download manager | URLSession background transfer service | NATIVE EQUIVALENT | iOS-native background downloads |
| Picture-in-Picture (pip.rs) | System PiP: AVKit (AVPlayer path) native; libmpv path via AVPictureInPictureController w/ sample-buffer layer (hard) | NATIVE EQUIVALENT | AVPlayer backend owns PiP; document libmpv limitation |
| HDR EDR overlay (hdr_overlay.rs) | iOS system EDR (Metal layer extended range) | REWRITE | MPVKit video-out gpu-next handles HDR→display; verify HDR10/DV playback matrix |
| Trickplay thumbs (thumbs.rs, ffmpeg) | Generate via AVAssetImageGenerator / libmpv screenshots | REWRITE | iOS-native generation + bounded cache |
| Subtitle extraction/sync (sub_extract.rs, subsync/) | Port logic (pure algorithms — moviehash, correlation) | REWRITE (port) | Rust subsync logic is portable → could run in-process; otherwise Swift port |
| WebView privacy blocker | WKContentRuleList | NATIVE EQUIVALENT | only for features that actually use WKWebView |
| External browser open (browser.rs) | ASWebAuthenticationSession / SFSafariViewController / openURL | NATIVE EQUIVALENT | — |
| Crash reporter (crash_report.rs) | MetricKit / os crash logs | NATIVE EQUIVALENT | MetricKit crash reporting + in-app diagnostics screen |
| Anime4K shaders (anime4k.rs) | libmpv user-shaders (`.glsl`) — runs inside mpv's renderer | REUSE (data) | MPVKit accepts user-shaders; ship shader files |
| Fonts management (fonts.rs, custom-fonts) | Install fonts in-app for rendering | REWRITE | CTFontManagerRegisterFontsForURL |
| Profiles/PIN/parental | standard iOS patterns | REWRITE | SwiftUI, Keychain-hashed PIN |
| stremio:// deep links | CFBundleURLTypes + Universal Links | NATIVE EQUIVALENT | register `stremio` + `harbor` schemes, validate |
| Local library (local_lib.rs) | Files app document picker + folder access (security-scoped bookmarks) | REWRITE | iOS-native local media |

## Known iOS lifecycle constraints (spec §86)

- Background: audio playback only via audio session; any other work must be short-tasked (BGTask) or URLSession background.
- Memory pressure: unbounded caches are fatal — every cache bounded + pressure-aware.
- Route changes (AirPlay/Bluetooth): AVAudioSession route-change notifications re-route audio.
- Network change: NWPathMonitor → cancel/retry in-flight addon & stream work.

## Items that remain genuinely unresolved (do not fake)

| Item | State |
|---|---|
| libmpv + system PiP | UNKNOWN — investigate MPVKit→AVSampleBufferDisplayLayer PiP; else AVPlayer-backend-only PiP |
| HDR10/Dolby Vision via MPVKit on device | UNKNOWN — needs on-device matrix test |
| Chromecast sender stability | UNKNOWN — investigate after player milestone |
| Multiview >2 tiles on A17 | UNKNOWN — device test |

Updates: whenever an audit or device test resolves an UNKNOWN, this file is updated in the same commit.
