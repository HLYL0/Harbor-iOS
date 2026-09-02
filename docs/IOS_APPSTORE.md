# IOS App Store Analysis

> Honest, feature-by-feature App Store classification (spec §89). Nothing here is legal advice; it is engineering distribution planning.
> Rule: we do not bypass App Review and we do not disguise functionality.

## Classification vocabulary

| Class | Meaning |
|---|---|
| APP STORE SAFE | conforms to App Store Review Guidelines as shipped |
| REVIEW RISK | reviewable, may need justification/screening UI |
| DISTRIBUTION RESTRICTED | technically possible but conflicts with guidelines (sideload-only) |
| NOT APPLICABLE | desktop-only or upstream-independent |

## Feature analysis (draft — refined by parity matrix)

| Feature area | Class | Notes |
|---|---|---|
| Stremio account login/sync (official API) | APP STORE SAFE | Stremio itself is on the App Store |
| Addon protocol client (user-installed addons, manifest URLs) | REVIEW RISK | depends on addon catalog curation; adult gating required (17+ rating + toggle) |
| Addon discovery store w/ community catalogs | REVIEW RISK | any storefront listing piracy-adjacent addons fails review; needs gating/curation policy |
| Cinemeta/TMDB metadata browsing | APP STORE SAFE | normal media-app metadata |
| Direct HTTPS playback (HLS/MP4) | APP STORE SAFE | |
| libmpv playback of arbitrary containers | APP STORE SAFE | codec support itself is legal (LGPL obligations aside) |
| **Torrent streaming (built-in engine)** | DISTRIBUTION RESTRICTED | violates 2.5.2/5.2.1 expectations; Harbor Desktop feature — iOS keeps debrid path only |
| **Real-Debrid / other debrid resolvers** | DISTRIBUTION RESTRICTED | resolvers for copyright-infringing content; historically rejected |
| Live TV via user-supplied M3U/Xtream playlists | REVIEW RISK | "own content" defense exists but bulk IPTV lists are review-fragile; needs personal-use framing |
| EPG/XMLTV | APP STORE SAFE (adjacent) | data display; depends on playlist source class |
| DVR recording of streams | REVIEW RISK | time-shifting of user-provided sources; App Store apps exist (e.g. IPTV players w/ record) |
| Subtitle downloads (OpenSubtitles etc.) | APP STORE SAFE | |
| Trakt/Simkl/MAL/AniList sync | APP STORE SAFE | official APIs |
| Watch Together (private relay) | APP STORE SAFE | group playback features exist (SharePlay) |
| Chromecast/DLNA casting | APP STORE SAFE | normal local-network feature |
| Local media from Files | APP STORE SAFE | |
| Custom theme CSS/JS | REVIEW RISK→RESTRICTED | arbitrary JS execution must be sandboxed/disabled in App Store builds |
| Discord/Telegram notifications | APP STORE SAFE | user-configured webhooks |
| Discord Rich Presence | NOT APPLICABLE on iOS | no OS IPC to Discord desktop |
| Backup/restore (.harbx) | APP STORE SAFE | as long as secrets stay in Keychain and export is explicit |

## Build profiles (spec §90)

| Profile | Contains | Purpose |
|---|---|---|
| SIDELOAD (current) | full capability incl. debrid resolver, addon store | LO's personal device; honest capability profile |
| APP STORE SAFE (future) | removes DISTRIBUTION RESTRICTED features; gates REVIEW RISK behind 17+ + user consent; sandboxed themes | would require LO's paid Apple Developer account |

No feature is ever shipped disguised: the sideload build is what it is, and an App Store build would be a reduced-capability product, not a hidden one.
