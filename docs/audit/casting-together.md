# Harbor v0.9.21 — Casting + Watch Together + Relay Subsystem Forensic Report

> Audit of the reference implementation cloned at `harbor-ref` (Windows).
> All paths below are relative to the repo root. Line references are from the audited snapshot.
> **FACT** = verified in source. **INFERENCE** = reasonable deduction not directly asserted by code/comments.

---

## 1. Casting Subsystem

### 1.1 Entry points and dispatch

All casting is funneled through **`src-tauri/src/cast.rs`** (1406 lines). Tauri commands (registered in `src-tauri/src/lib.rs:641-754`):

| Command | Purpose |
|---|---|
| `cast_discover` | Parallel discovery across 4 protocols, dedupe + sort |
| `cast_load` | Load media on a device (serialized via a global load gate) |
| `cast_play` / `cast_pause` / `cast_seek` | Control the *active* session (protocol dispatch) |
| `cast_stop` | Tear down active session + HLS session + subtitle temp files |
| `cast_status` | Poll position/state of the active session |

Frontend wrapper: **`src/lib/cast.ts`** (invoke wrappers + content-type guessing). Capability/compatibility logic: **`src/lib/cast/device-caps.ts`**.

**Single-active-session model.** One global `ACTIVE: Mutex<Option<ActiveSession>>` (`cast.rs:131`). A new `cast_load`:
1. Registers a "pending load" generation (newest request wins — older generations get cancelled and their device session + HLS session cleaned up, `cast.rs:133-208, 322-369`).
2. Serializes through `CAST_LOAD_GATE`.
3. Prepares subtitles (optional burn-in), decides remux/transcode, registers the stream with the proxy, then dispatches per protocol.
4. Commits the session to `ACTIVE` only if its generation is still current ("cast load superseded" otherwise).

### 1.2 Casting targets & protocols

| | **Chromecast** | **DLNA/UPnP** | **Roku** | **AirPlay (legacy)** |
|---|---|---|---|---|
| Discovery | mDNS `_googlecast._tcp.local.` (mdns-sd crate, 5 s window) | SSDP M-SEARCH ×4 bursts + passive NOTIFY listener on :1900 | SSDP M-SEARCH `roku:ecp` | mDNS `_airplay._tcp.local.` + `/server-info` probe to drop AirPlay-2-pairing devices |
| Load | Cast V2 protocol: launch receiver app, MEDIA LOAD with `currentTime` | SOAP `SetAVTransportURI` + `Play` + `Seek` (REL_TIME hh:mm:ss) | ECP deep-link launch into "Media Assistant" channel (`launch/{id}?u=…&streamformat=…&startMS=…`) | Legacy `/play` POST with `Content-Location` + `Start-Position: 0`, then `/scrub` |
| Play/Pause | Media channel `play`/`pause` | SOAP `Play` / `Pause` (Speed 1) | ECP `keypress/Play` (both play & pause) | `/rate?value=1.0` / `0.0` |
| Seek | Media channel `seek` — **relative**: `sec - seek_start` (`cast.rs:1198-1199`) | SOAP `Seek` REL_TIME | **Not implemented** — no-op with a documented stderr note (`roku.rs:356-359`); the supported path is re-launch with `startMS` | `/scrub?position={sec}` |
| Stop | `receiver.stop_app(session_id)` | SOAP `Stop` | ECP `keypress/Home` | `/stop` |
| Status | Media channel `get_status`; position = cast pos + `seek_start` (`cast.rs:1299`) | `GetPositionInfo` + `GetTransportInfo` (RelTime parsed hh:mm:ss) | `query/media-player` XML (position/duration ms, player state, error attr) | `/playback-info` plist (`position`, `rate` → PLAYING/PAUSED) |
| Subtitles | Burned-in only (via transcode) | Burned-in only | Burned-in only | Burned-in only |
| Start offset | LOAD `currentTime` for direct MP4; HLS sessions start pre-seeked in ffmpeg (`-ss`) | SOAP Seek after 1.2 s delay, retried once | `startMS` on launch | scrub after 1.2 s |
| Protocol details | Vendored `rust_cast` 0.20.0 (`src-tauri/vendor/rust_cast`); `connect_without_host_verification`; heartbeat ping/pong loop on a dedicated thread (`cast.rs:1040-1063`) | Vendor classification: Samsung / LG WebOS / Sony Bravia / Panasonic / Hisense Vidaa / Other (`dlna.rs:28-54`); Samsung fallback desc URLs `smp_2_`…`smp_20_`, `:9197/dmr`, `:9999/dmr`, `:9080/dmr`, `:7677/dmr` (`dlna.rs:180-200`) | Channel located via `query/apps` scan for "media assistant" or fixed id `782875`, with icon probe fallback and rich errors (`ROKU_ECP_BLOCKED`, `ROKU_MEDIA_ASSISTANT_MISSING`…) | UA `MediaControl/1.0`; per-load UUID session id header; 403/404 give actionable TV-side instructions (`airplay.rs:160-171`) |

**Chromecast receiver app**: `HARBOR_RECEIVER_APP_ID = "120F754D"` (`cast.rs:25`) — not one of Google's default receiver IDs (CC1AD845 / 4F8B3483). **INFERENCE:** a Harbor-registered custom web receiver (styled media receiver or bespoke) hosted by Harbor; no receiver HTML ships in this repo.

### 1.3 HLS remux / transcode emitter — `src-tauri/src/cast_hls.rs` (706 lines)

Decision logic in `cast_load` (`cast.rs:40-53, 707-746`):
- `needs_auto_remux(kind, url)`: chromecast/dlna/roku + URL that is **not** `.m3u8`/`.mpd`/`.ts` → remux. Rationale in comment: non-faststart MP4 (moov-at-end) and MKV stall the Chromecast.
- Roku additionally forces transcode of any non-streaming URL (`roku_force_transcode`).
- Effective profile: re-encode only if the frontend supplied one; auto-remux uses copy-friendly defaults (`max_height 1080`, no forced codecs — the ffmpeg invocation below re-encodes video regardless when the HLS path runs; see note).
- Burned-in subtitle forces the transcode path.

Pipeline (`cast_hls.rs`):
- `ffprobe` source (codecs, W×H, fps, bitrate, duration; 15 s timeout; `-user_agent` + `-headers` pass-through).
- Continuous `ffmpeg`: `libx264 high 4.1 veryfast crf 23`, `-g 144 -keyint_min 144 -sc_threshold 0 -x264-params scenecut=0:open_gop=0`, `aac 192k stereo`, scale-clamp ≤1080, optional `subtitles=<path>:force_style=…` burn filter, `-f hls -hls_time 6 -hls_list_size 8` sliding playlist (`delete_segments+independent_segments+temp_file`).
- **FACT/note:** the comment in `cast.rs` claims "copy mode / fast transmux for h264+aac — no CPU cost", but the emitted HLS command re-encodes video with `-c:v libx264` in the code read; the "fast transmux" claim appears stale relative to the current command line.
- Served by axum router: `GET /cast/hls/{id}/master.m3u8`, `variant.m3u8`, `{file}.ts` with CORS headers; master playlist hardcodes CODECS `avc1.640029,mp4a.40.2`; segment/playlist handlers poll for readiness (20 s max); idle eviction + kill/reap/rmdir cleanup.

### 1.4 Stream proxy — `src-tauri/src/stream_proxy.rs`

`register_cast` (`stream_proxy.rs:150-229`) picks, in order:
1. **HLS session** (`/cast/hls/{id}/master.m3u8`) when transcode/burn-sub is required — URL uses the **LAN-reachable IP** of this machine (not localhost) so the TV can fetch it.
2. **Playlist proxy** (`/p/{id}/{last_seg}`) for HLS/DASH sources needing header forwarding without transcode.
3. **Direct stream** (`/s/{id}` or `/s/{id}.ts` when transcoding) as fallback.

### 1.5 Subtitles — `src-tauri/src/cast_subs.rs` (435 lines)

- Sources: external URL (download, gzip-transparent, 8 MB cap, cancellable) / local file / **embedded** stream extraction (`ffmpeg -map 0:s:{src_index}`).
- Format sniff: srt/ass/ssa/vtt; VTT converted to SRT via ffmpeg.
- Style → ASS `force_style`: font size, colors (hex→`&HBGR`), border, Alignment (left=1/center=2/right=3), MarginV (`build_force_style`, `cast_subs.rs:110-123`).
- Burn filter string: `subtitles='<escaped path>':force_style='…'` with Windows drive-colon escaping.

### 1.6 Capability matrix — `src/lib/cast/device-caps.ts` (358 lines)

Static per-model caps (Nest Hub/Ultra/CCwGTV 4K+HD/Fire TV/Roku/DLNA vendors/Apple TV/AirPlay): max resolution, HEVC/AV1/DoVi/HDR10, AC3/EAC3/TrueHD/DTS passthrough, MKV container. Functions:
- `checkStreamCompat(stream, caps)` → list of reasons (used for UI warnings).
- `pickBestCompatStream` → highest-res compatible stream.
- `pickTranscodeProfile` → `{max_height, force_h264, force_aac, force_stereo, max_video_kbps}` derived from stream codec strings vs caps.
- `needsTranscode`.

### 1.7 Discovery details

- Chromecast/AirPlay use `mdns-sd` `ServiceDaemon::browse` in a `spawn_blocking`, 5 s deadline, dedupe map keyed `cc-{host}:{port}` / `airplay-{host}:{port}`; IPv4 preferred (link-local v6 excluded).
- DLNA SSDP: M-SEARCH for MediaRenderer/AVTransport/Dial + `ssdp:all` over every local IPv4 interface, plus passive NOTIFY socket on 1900 (Samsung TVs) (`dlna.rs:227-242`).
- Roku SSDP: `roku:ecp`, drops candidates not on port 8060.
- AirPlay: mDNS + `GET /server-info` (900 ms timeout) — drop if 403/404 or body mentions `requiressenderfeatures`/`hkpairing` (AirPlay 2 / HomeKit-only devices unsupported — legacy protocol only).
- Merge: dedupe by host IP with kind priority `chromecast > airplay > roku > dlna`, except Apple-named devices keep AirPlay over DLNA (`cast.rs:515-558`); `audio_only` heuristic from name/model (speaker vs screen).

### 1.8 Casting ↔ Watch Together interplay

- Host publishing while casting: 3 s interval loop publishing cast position/playing (`use-room-sync.ts:273-298`).
- Incoming sync while casting: state/commands are applied to the cast device (seek/play/pause with the same drift logic, `use-room-sync.ts:244-271`); non-cast apply paths are skipped when casting.
- `use-cast-return-publish.ts`: when a cast session ends, the host immediately re-publishes local-player state so guests re-converge.

### 1.9 `cast_server.rs` & `web_server.rs` (adjacent, often conflated)

- **`src-tauri/src/cast_server.rs`** (61 lines): legacy-named — actually manages the bundled `stremio-server` sidecar (kill orphans via `taskkill`/`pkill`, status, restart, stop). Not a cast streaming server.
- **`src-tauri/src/web_server.rs`** (280 lines): serves the Harbor web UI + **phone remote control** WebSocket (`/api/remote`) on port **11471** (`0.0.0.0`), broadcast channel (256) + client count, Tauri events `remote://client`/`remote://cmd`. **FACT:** this is the phone-remote signaling channel, **not** the Watch Together relay (the together relay lives on Cloudflare, §3).

---

## 2. Watch Together Subsystem

UI: `src/components/together-modal.tsx` (+ `together-modal/*`), `together-cursors.tsx`, `together-*-toast.tsx`, `together-deploy-modal.tsx`, `together-relay-banner.tsx`, `together-leave-for-live-modal.tsx`.
Logic: `src/lib/together/*`. Player integration: `src/views/player.tsx` + `src/views/player/hooks/use-{room-sync,lobby-gate,host-source,cast-return-publish,player-exit,draw-mode}.ts`. Constants: `src/views/player/player-utils.ts`.

### 2.1 Room lifecycle

- **Room codes**: 6 chars from alphabet `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (no 0/1/I/O), crypto-random (`protocol.ts:149-164`); input normalized (uppercase, strip non-alnum, cap 6); relay accepts `/r/[A-Z0-9]{4,8}` (worker.js:28).
- **Create**: `startSession()` generates code client-side, then `join(code)`. **Join**: code or invite link (parses `harbor-relay` + `harbor-room` query params; invite links built as `https://app.harbor.site/?harbor-relay=wss://…&harbor-room=CODE`, `invite.ts:11-35`). Joining a different relay via link auto-updates `settings.togetherRelayUrl` then joins (`provider.tsx:290-313`).
- **Identity**: persistent random `clientId` + display name in localStorage (default `Guest NNNN`); profile updates broadcast as `participant-profile`. Name collisions auto-renamed to `Name (2)…` (max 8 attempts) with a 60 ms reconnect (`client.ts:540-563`).
- **Host**: first joiner becomes host (server-side). Host reassignment on leave → **earliest-joined remaining participant** (`worker.js:375-384`); explicit `host-leaving` announcement; `claim-host {fresh:true}` resets `started` and everyone's `ready`.
- **Lobby gate**: guests report `ready` once their player reports video dimensions + duration (`use-room-sync.ts:309-319`). Host UI marks participants stale if not ready within `READY_STALE_MS = 20 s` (`use-lobby-gate.ts:84-99`). Host presses **Start** → `start` message → relay flips `started:true` (persisted). Guests auto-advance on `started`.
- **Guest escape hatch**: after `GUEST_ESCAPE_MS = 45 s` un-started, guest can "play without sync" (`playWithoutSync`).
- **Empty room GC**: when last peer leaves and room idle > `ROOM_IDLE_MS` (6 h), stored state/host reset (worker.js:552-557).

### 2.2 Sync protocol (play/pause/seek)

Message surface in `src/lib/together/protocol.ts` (client `t:` types: hello, profile, leave, state, cmd, chat, invite, ready, host-leaving, claim-host, start, summon, cursor, draw, presence, ping; server: joined, participant-joined/left/ready/profile, host, host-leaving, started, state, cmd, chat, invite, summon, cursor, draw, presence, error, pong). Protocol version gates: `WT_PROTO = 2`, relay `WORKER_VERSION = 11`, client requires `REQUIRED_RELAY_VERSION = 10`.

**Host authority** (`worker.js:471-499`):
- Full `SyncState {mediaId, mediaTitle, episode, posterUrl, positionSeconds, playing, speed, source, guestPick, updatedAt, updatedBy, hostClientId}`.
- Once a host exists, only the host's `state` writes are accepted (guests' are dropped); pre-host, any peer may write but is throttled (≥500 ms between writes, reject if older than stored `updatedAt - 2000`).
- Relay stamps every state broadcast with `srvAt` and persists last state.

**Host publishing** (`use-room-sync.ts:98-125`): every `HOST_HEARTBEAT_MS = 1000 ms`, the host publishes position + playing + rate + source descriptor (from its active torrent stream: `SourceDescriptor {title, resolution, sizeBytes, infoHash, fileIdx, durationSec}` — `host-stream.ts`, `source-descriptor.ts`). Guests use `source-match.ts` to re-rank their own stream lists toward the same file (infoHash match = 1000 pts, resolution 200, size-drift 150, title-token Jaccard 120, release group 40; badges `same`/`close` at ≥1000/≥300).

**Commands (guest → host)**: `cmd` play/pause/seek only, forwarded exclusively to the host socket (`worker.js:501-516`). Seek carries `seq` (monotonic per sender) + `at`; **seek coalescing** 250 ms and 120 ms apply debounce (`seek-coalesce.ts`, `use-room-sync.ts:176-185`); stale `seq` ignored.

**Apply (guests)** (`use-room-sync.ts:190-242`):
- Skip own echoes (`updatedBy === clientId`) and out-of-order (`updatedAt < lastApplied`).
- Target position = `positionSeconds + ageS + SYNC_PLAY_LOOKAHEAD_S` (when playing), age clamped to `SYNC_MAX_AGE_S = 30 s`, lookahead `0.4 s`.
- Act only if play-state changed or drift > `SYNC_DRIFT_TOLERANCE_S = 0.6 s`; else drift is tolerated (no re-seek).
- Catch-up state machine: after a corrective seek, stay tolerant until drift < `SYNC_SEEK_JUMP_S = 10 s` (or buffering constraints), then resume strict sync.
- Rate sync: `speed` applied when off by >0.01.
- **Echo suppression**: after applying a foreign state/command, outgoing publishes suppressed for `SYNC_SUPPRESS_MS = 1400 ms` (`client.ts:125-127`).

**Clock correction / RTT adjustment** (`client.ts:565-610`):
- Ping every `PING_INTERVAL_MS = 25 s`; server answers `{t:"pong", srvAt}`.
- `rtt = now - pingSentAt` (samples >10 s discarded); `sample = srvAt - (pingSentAt + rtt/2)`; offset EMA: first sample seeds, then `offset = 0.7*offset + 0.3*sample`.
- Incoming `state.updatedAt` rewritten to local clock: `updatedAt = srvAt - relayOffset` (`localizeStateClock`); fallback `relayOffset = srvAt - Date.now()` until first RTT sample. This is what makes the age-based position extrapolation (`position + age`) correct per client.
- Liveness: socket killed if no inbound for 40 s; reconnect exponential 1 s→30 s with jitter; connect watchdog 10 s; terminal error after 4 (or 12 if ever joined) failures, with `diagnoseRelayFailure` hitting relay `/health`.

**Late join**: `joined` carries full participant list + last `syncState` + `hostClientId` + `started` + `relayVersion`. In lobby: if host state is paused and position differs >1.5 s, guest seeks to it and stays paused (`use-room-sync.ts:321-337`). After start: guest applies initial sync (rate, seek to extrapolated target, play) with suppression (`use-room-sync.ts:367-388`).

### 2.3 Chat, cursors, drawing, presence, summon

- **Chat**: text trimmed/capped 500 chars, broadcast with from/name/at; UI keeps last 200 locally (`provider-events.ts:15,79-80`; `chat-panel.tsx`).
- **Cursors**: normalized (0..1) coordinates relative to the active `<main>` scroll container (`together-cursors.tsx:46-55`); send ≤ every 60 ms while moving; hidden on idle (1.5 s), blur, tab-hidden, path change; each message carries `path` (route) so cursors only render on the same route; remote cursors expire after 6 s of silence; rendered as SVG pointers with participant color/name. Setting `togetherShareCursors` (default on).
- **Drawing**: player overlay strokes (`use-draw-mode.ts`, `components/player/draw-canvas.tsx`) with phases `start/point/end/clear`, strokeId (≤64), color, path-scoped; GC after 9.5 s; `clear` wipes a path's strokes; only when >1 participant in room.
- **Presence**: heartbeat carrying optional `ParticipantLocation` (home/discover/anime/queue/addons/settings/service/addon-detail/person/meta/picker/player + media meta) — powers `participantLocations` and `hostLocation` (where the host is).
- **Summon**: any peer can broadcast a `target` (mediaId+view whitelist, or view in [home, discover, anime, queue, addons]); receivers show a toast (auto-dismiss 14 s) offering to navigate.
- **Invite**: `invite` broadcast carries `PlayInvite` (media + episode + artwork + `proto: WT_PROTO` + `guestPick` + source). Host re-sends last invite on reconnect and to newly joined participants (`client.ts:416-429`). `wasInvitedTo` window = 60 s.
- **Guest pick**: `guestPick` flag lets guests open the picker; `deriveRoomGuestPick` resolves from newest of state vs invite (`room-derive.ts:38-50`); host-only toggle in modal.
- **Host leaving**: closing the player as host publishes a null state, sends `host-leaving`, clears invite (`use-player-exit.ts:72-83`); relay then reassigns host and guests get a toast + option to return to the media.

### 2.4 Relay client resilience (client.ts)

Out-queue (non-ephemeral messages buffered while offline; `state` messages coalesced), invite/host-claim replay on reconnect, name-collision reconnect, terminal failure diagnosis.

---

## 3. Relay (Cloudflare) Architecture

### 3.1 Deployment controller — `src-tauri/src/cf_relay.rs` (251 lines)

Tauri commands (`cf_list_accounts`, `cf_deploy_relay`, `cf_delete_relay`, `cf_relay_status`), frontend in `src/lib/together/cf-deploy.ts` and `src/components/together-deploy-modal.tsx`.

- **Auth**: user-supplied Cloudflare API bearer token (stored in settings `togetherCfToken`/`togetherCfAccountId`; NOT persisted server-side).
- **List accounts**: `GET /client/v4/accounts`.
- **Check**: script existence via `GET …/workers/scripts/harbor-together-relay`; workers.dev subdomain via `GET …/workers/subdomain` (hard error if unset).
- **Deploy**: multipart PUT of `metadata` + embedded `worker.js` (`include_str!("../relay/worker.js")`, `WORKER_JS`) to `/accounts/{id}/workers/scripts/harbor-together-relay`, then `POST …/subdomain {enabled:true}`, returns `wss://harbor-together-relay.{subdomain}.workers.dev`.
- **Metadata**: `main_module: worker.js`, `compatibility_date: 2026-05-01`, Durable Object namespace binding `ROOM`/class `Room`; **first deploy includes `migrations: {tag:"v1", new_sqlite_classes:["Room"]}`** (SQLite-backed DO storage). Retry ladder: namespace propagation (error 10065 / "already in use" + namespace) retried with backoff [1.5, 2.5, 4, 6, 8, 10 s]; migration errors (10074 / "already depend" / missing_migration) fall back to metadata without migrations.
- **Delete**: `DELETE …?force=true`; 404 treated as success. **Status**: GET script → HTTP 2xx.

### 3.2 Relay server — `src-tauri/relay/worker.js` (571 lines)

Cloudflare Worker + one Durable Object (`Room`) **per room code** (`idFromName`), so state survives client disconnects and DO hibernation (websocket attachments rehydrated on wake; `syncState`/`hostClientId`/`started` persisted in DO storage).

- Routes: `/` & `/health` → `{ok, version, hosts}` (CORS *); `/proxy` → restricted fetch proxy; `/r/{CODE}` → WebSocket upgrade (426 otherwise).
- **Message routing** (`onMessage`): hello, profile, leave, state, cmd, chat, invite, ready, host-leaving, claim-host, start, summon, cursor, draw, presence, ping→pong.
- **Sanitization** (input hygiene is the main security boundary — **no auth on room join; the room code is the credential**):
  - avatar: data:image/(png|webp|jpeg|gif);base64 or http(s), ≤600 KB;
  - color: `#rrggbb` only; name ≤32; chat ≤500; invite fields capped (mediaId ≤256, poster/background/logo ≤2000, title ≤300, proto 0-99);
  - state: position ≥0 finite, `updatedAt` finite, `playing` boolean, `updatedBy` must equal sender's clientId; source descriptor sanitized (title ≤200, resolution ≤16, infoHash `/^[0-9a-fA-F]{16,64}$/`, non-negative numbers); `guestPick` only if true;
  - cursor x/y numeric; draw phases whitelisted, strokeId 1-64 (except clear); summon targets whitelisted.
- **Duplicate clientId**: newer socket replaces older (older closed with "replaced").
- **`/proxy`**: allowlisted hosts (knaben, apibay, 1337x, yts, eztv, nyaa, bitsearch, rutor, torrentio.strem.fun, torbox, cinemeta, opensubtitles ×3), HTTPS-only, GET/POST/OPTIONS with CORS, rate limit 60 req/min per `cf-connecting-ip`.
- **Versioning**: `WORKER_VERSION = 11` advertised on `joined`; client banners "relay outdated" below version 10 (`relay-version.ts`, `together-relay-banner.tsx`).
- **Public relay**: `wss://pub.harbor.site` (`HARBOR_PUBLIC_RELAY`) — same worker deployed at Harbor's own domain; user relays are per-account.

### 3.3 Web front — `src-tauri/relay/harbor-web.nginx`

Nginx for the hosted web app (`app.harborstremio.com`; the client invite base is `app.harbor.site` — **INFERENCE:** `.site` is the current brand domain, the nginx file may be legacy): HTTP basic auth ("Harbor (private alpha)"), robots noindex, `no-referrer`, no cookies forwarded, `/api-proxy/…` with a large allowlist (debrid/torrent/metadata hosts + `*.workers.dev`, `*.strem.fun`, `*.strem.io`, `*.stremio.homes`, `*.elfhosted.com`, `*.vercel.app`, etc.) using `Authorization: $http_x_harbor_auth` forwarding — i.e., the web app proxies addon/debrid traffic through this host.

---

## 4. Local Network Discovery Summary

| Protocol | Mechanism | File |
|---|---|---|
| Chromecast | mDNS `_googlecast._tcp.local.` (mdns-sd), 5 s browse, props `fn`/`md` | `cast.rs:394-446` |
| DLNA | SSDP M-SEARCH (4 bursts × 6 STs) + passive NOTIFY on 239.255.255.250:1900, per-iface sockets | `dlna.rs:202-280` |
| Roku | SSDP M-SEARCH `roku:ecp`, port-8060 filter | `roku.rs:26-96` |
| AirPlay | mDNS `_airplay._tcp.local.` + `/server-info` capability probe (legacy-only filter) | `airplay.rs:30-124` |
| LAN IP for HLS serving | UDP connect-probe to 1.1.1.1/8.8.8.8/192.168.1.1:80 per iface | `dlna.rs:318-335` |

mDNS (`mdns-sd`) is used for Chromecast + AirPlay only; DLNA/Roku use raw SSDP. All discovery runs in `spawn_blocking` with a shared 5 s timeout, merged/deduped/sorted in `cast_discover`.

---

## 5. FACT vs INFERENCE

### FACT (directly present in source)

1. Four cast targets with the exact control verbs above; Roku seek is an explicit no-op.
2. HLS remux emitter exists and is auto-selected for non-streaming URLs on cc/dlna/roku; the emitted ffmpeg command **re-encodes** with libx264/aac (the "copy-mode, no CPU cost" comment in `cast.rs` contradicts the actual `-c:v libx264` in `cast_hls.rs`).
3. Chromecast uses custom receiver app id `120F754D` (not a Google default receiver id).
4. AirPlay support is **legacy-RAOP-only**; AirPlay-2/HomeKit-pairing devices are filtered out at discovery and 403s are explained in-app.
5. Watch Together relay = Cloudflare Worker + SQLite Durable Object per room; user-deployable via cf_relay.rs commands; public relay `wss://pub.harbor.site`; client requires relay version ≥10; current worker version 11.
6. Host-authoritative state writes; 1 s host heartbeat; RTT-based clock localization (EMA 0.7/0.3); 0.6 s drift tolerance; 0.4 s lookahead; 30 s age clamp; 10 s catch-up jump; 1.4 s echo suppression; 250/120 ms seek coalescing/debounce; `started`/`ready` lobby gating (20 s stale, 45 s guest escape).
7. Relay has **no authentication** on room join — room code is the only credential; all message fields sanitized; `/proxy` allowlisted + rate-limited.
8. Phone remote (`web_server.rs`, port 11471) is a separate local server from the Cloudflare together relay.

### INFERENCE (reasonably deduced, not stated)

1. The `120F754D` receiver is a Harbor-registered Cast receiver (possibly a styled/bespoke media receiver); its hosting and exact behavior are not in this repo.
2. `app.harbor.site` (client) vs `app.harborstremio.com` (nginx) — a domain rename happened; the nginx file is likely legacy config kept for reference.
3. The relay's practical participant limits and the "daily limit" wording in `diagnoseRelayFailure` imply Cloudflare free-tier constraints, but no explicit cap logic exists in the worker beyond the `/proxy` rate limit.
4. The "no video data touches the relay" UI claim is consistent with the design (only control metadata flows), but nothing in the worker technically *prevents* other message types.
5. Host heartbeat + seek coalescing parameters were tuned empirically for TV-sized latencies; no tuning notes exist in-repo.

---

## 6. Top 5 Parity-Critical Behaviors (for an iOS rebuild)

1. **Host-authoritative sync loop with clock localization.** Host publishes full SyncState at 1 Hz; relay gates writes to the host only; every broadcast carries `srvAt`; clients maintain an RTT-corrected relay offset (EMA 0.7/0.3, fallback to `srvAt - now`) and rewrite `updatedAt` into local time before extrapolating `target = position + age + 0.4 s`. Getting this wrong breaks position convergence entirely.
2. **Drift-tolerant apply with echo suppression.** Act only on play-state change or drift >0.6 s; clamp age to 30 s; catch-up mode until drift <10 s; suppress outgoing publishes 1.4 s after every applied foreign state; coalesce seeks (250 ms) with per-sender monotonic seq + 120 ms debounce; skip own echoes and out-of-order states. These are the anti-feedback-loop invariants.
3. **Room lifecycle on the Durable Object.** First-joiner-is-host, reassignment to earliest-joined on leave, host-leaving broadcast, claim-host(fresh) resetting started/ready, ready-based lobby gate (20 s stale marking, 45 s guest escape), persistence across DO hibernation (attachments + SQLite storage), 6 h idle reset, duplicate-clientId replacement, and version gating (worker v11 / required v10 / WT_PROTO 2).
4. **Auto-remux/HLS emitter + LAN-IP proxying + subtitle burn-in.** Non-streaming sources → ffprobe + continuous ffmpeg HLS (6 s segments, sliding 8, ≤1080, aac stereo, keyint 144) served at a LAN-reachable IP; per-device capability matrix drives compatibility warnings, best-stream selection, and transcode profiles; subtitle burn-in with ASS force_style (VTT→SRT, embedded extraction). This is what makes "cast anything to anything" work.
5. **Per-device protocol quirks.** Chromecast relative-seek accounting (`seek_start` offset, HLS starts at 0 with pre-seeked ffmpeg); DLNA vendor matrix (Sony pre-Stop + delays + `AVC_MP4_MP_HD_AC3` DIDL profiles, Samsung `smp_*` fallback URLs, live MIME `video/mpeg` vs `video/mp2t`); Roku Media Assistant channel launch (id 782875) + keypress controls + no-op seek + `startMS`; legacy-AirPlay-only filter + `/rate`/`/scrub` semantics. iOS parity on real TVs hinges on replicating these, not just the happy paths.
