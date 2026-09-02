# IOS Casting

> CastingManager design (spec §57). Behavior source: `docs/audit/casting-together.md` (verified). Discovery protocols are standard network protocols — portable to iOS with the network entitlement; AirPlay is a native system capability.

## 1. Harbor casting model (FACT)

| Target | Discovery | Control | Notes |
|---|---|---|---|
| Chromecast | mDNS `_googlecast._tcp.local.` | DIAL/Cast protocol (`rust_cast` vendor) | play/pause/seek/stop, subtitles |
| DLNA | SSDP M-SEARCH (4 bursts × 6 STs) | SOAP AVTransport | play/pause/seek/stop |
| Roku | SSDP `roku:ecp` (port 8060) | ECP HTTP | **seek is an explicit no-op** (FACT) |
| AirPlay | mDNS `_airplay._tcp.local.` + `/server-info` probe | custom server (desktop-only) | legacy-only filter |

All desktop casting flows through a local HTTP server + ffmpeg HLS remux (re-encodes libx264/aac) — a desktop mechanism that iOS cannot and need not replicate for AirPlay (system) but must replace for Chromecast/DLNA (senders speak to the receiver directly).

## 2. iOS CastingManager

```
CastingManager (discovery + session lifecycle)
 ├── AirPlayAdapter    → system playback routes (AVRoutePickerView / AVPlayer routes) — NATIVE EQUIVALENT
 ├── ChromecastAdapter → mDNS + Cast sender protocol (custom impl or audited OSS lib)
 ├── DLNAAdapter       → SSDP + SOAP AVTransport control point (HTTP)
 └── RokuAdapter       → SSDP roku:ecp + ECP keypress/launch (HTTP; seek no-op parity)
```

- Discovery: `NWBrowser` (Bonjour) for _googlecast/_airplay; raw SSDP via UDP socket for DLNA/Roku — with the same 5s shared timeout and merged/deduped results as Harbor.
- Local network permission (NSLocalNetworkUsageDescription) added only when casting lands.
- Media format: receivers play the source URL directly where supported (HLS-friendly sources); no local transcode server on iOS (documented in platform gap). Subtitle burn-in unavailable → document limitation; DLNA subtitle sidecar where receiver supports it.

## 3. Priority & status

| Target | Priority | Status |
|---|---|---|
| AirPlay | P1 | NATIVE EQUIVALENT — system routes, zero custom code |
| Chromecast | P2 | UNKNOWN (needs protocol sender audit; investigate after player milestone) |
| DLNA | P2 | REWRITE (small — HTTP control point) |
| Roku | P3 | REWRITE (small — ECP) |

No fake casting: each adapter ships only when its protocol path is verified against a real receiver (spec §101).
