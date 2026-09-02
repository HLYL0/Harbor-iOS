# IOS Watch Together

> Room client + relay integration design (spec §58–59). Behavior source: `docs/audit/casting-together.md` (verified). The entire client protocol is portable — this is one of the highest-parity features.

## 1. Relay architecture (unchanged — external)

- Relay = Cloudflare Worker + **Durable Object per room** (SQLite-backed state, survives hibernation).
- Protocol: `WT_PROTO = 2`, `WORKER_VERSION = 11`, client requires ≥10.
- **No auth — the room code IS the credential.** Same sanitization boundary must be enforced client-side.
- Public relay: `wss://pub.harbor.site`. User relays: per-account Cloudflare deploys.
- **iOS parity**: we ship as a room client; relay remains external. iOS CAN also run the deploy flow (the cf_relay commands are plain HTTPS API calls with a user token) — Phase 18 optional.

## 2. Room lifecycle (port constants exactly)

- 6-char codes from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (no 0/1/I/O), crypto-random; input normalization.
- Host = first joiner; reassignment on leave → earliest-joined remaining.
- Lobby gate: ready = video dimensions + duration reported; `READY_STALE_MS = 20 s`; host Start flips `started`.
- `GUEST_ESCAPE_MS = 45 s` → "play without sync" option.
- Identity: persistent clientId + display name (auto-rename on collision, max 8 attempts).
- Empty room GC 6 h.

## 3. Sync protocol (port exactly)

- Host heartbeat `1000 ms`: position + playing + rate + SourceDescriptor.
- Guest apply: target = `position + ageS + 0.4s` lookahead (when playing), age clamped `30 s`, act only if drift > `0.6 s`; corrective-seek catch-up until drift < `10 s`; rate sync at >0.01; echo suppression `1400 ms`; seek coalescing `250 ms` / 120 ms apply debounce; stale seq ignored.
- **Clock correction**: ping `25 s`, RTT samples (>10s discarded), offset EMA `0.7/0.3`, `srvAt` → local clock localization.
- Commands (guest→host): play/pause/seek only, forwarded to host socket.
- Late join: full state snapshot, lobby seek-if-paused (>1.5s), initial sync with suppression.
- Source matching for guests: infoHash 1000 / resolution 200 / size-drift 150 / title Jaccard 120 / release-group 40; badges same/close at ≥1000/≥300.

## 4. Social surface

Chat (500-char cap, last 200 local), cursors (0..1 normalized, ≤60ms sends, 6s expiry, route-scoped), drawing (start/point/end/clear, 9.5s GC), presence locations, summon (media/view whitelist, 14s toast), invites (60s window, re-sent on reconnect), guest-pick toggle, host-leaving handoff.

## 5. iOS implementation notes

- `URLSessionWebSocketTask` (native) with the same reconnect ladder (1s→30s jittered, 10s watchdog, terminal after 4/12 failures + `/health` diagnosis).
- SwiftUI: cursors as overlay views, draw canvas as `Canvas`, chat sheet, lobby gate states.
- Send side: sanitization identical to the relay's expectations (client validates before send).
- Keys/secrets: none (room code is the credential); invite links open via the app's universal/deep link (`app.harbor.site/?harbor-relay=…&harbor-room=…` parsing port).

## 6. Windows-testable

Room-code generation, invite parsing, clock-offset EMA, seek coalescing, drift decision function, source-match scoring. All pure functions → Swift unit tests + Python mirror.
