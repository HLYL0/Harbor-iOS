# Harbor iOS

A native SwiftUI iPhone/iPad client for the Stremio addon protocol, modeled after Harbor's browse and source-picker flow. Playback uses Apple's `AVPlayer`/`AVKit` rather than Harbor Desktop's libmpv process.

## Working MVP

- Cinemeta top movies, top series, metadata, episodes, and search
- Stremio email sign-in with the returned auth key stored in iOS Keychain
- Cloud addon collection sync plus account-scoped manual `manifest.json` installation
- Concurrent stream requests across compatible addons
- Direct HTTPS/HLS/MP4 source ranking and native playback
- Playback via libmpv (NuvioMedia/MPVKit): MKV, AVI, WebM, DASH, soft subtitles, and header-protected sources all play natively
- Real-Debrid resolution for torrent (`infoHash`) sources: `addMagnet → selectFiles → unrestrict` in the client, key stored in Keychain
- Cleartext HTTP and external sources remain visible and are marked as needing a resolver
- Native dark Harbor visual system and original Harbor icon

## Intentional first-build limits

Harbor Desktop ships a local torrent engine, local proxies, transcoding, DLNA, DVR, and multiview. Those executables cannot simply be copied into an iOS app. This first iOS target plays direct HTTPS sources through libmpv (any container/codec the bundled build supports) and resolves torrent sources through Real-Debrid. Built-in torrenting, transcoding, and multi-view remain later slices.

## Build from Windows

The source is authored on Windows. GitHub Actions runs Xcode on `macos-15`, executes the unit tests, builds an unsigned device app, verifies the IPA structure and bundled `Info.plist`, then uploads `Harbor-iOS-unsigned-ipa`.

1. Push this folder to a GitHub repository.
2. Open **Actions → Build Harbor iOS IPA**.
3. Download the artifact after the run is green.
4. Extract `HarborIOS.ipa` and sideload it with AltStore or Sideloadly.

A free Apple ID signs for seven days. AltStore can refresh the app while the Windows PC and iPhone are on the same network. Do not share Apple ID credentials; enter them directly into AltStore/Sideloadly.

## Architecture

```text
HarborIOS/     app entry, environment, root navigation, resources
Core/          design system
Data/          URLSession client and Keychain-backed session/addon storage
Domain/        Stremio DTOs, endpoint builder, service contracts
Features/      Home, details/source picker, player, settings
HarborIOSTests domain contract tests
```

## Source reference

Behavior was mapped from `harborstremio/harbor` commit `0117755`, particularly:

- `src/lib/addons.ts`
- `src/lib/cinemeta.ts`
- `src/lib/stremio.ts`
- `src/lib/streams/addons.ts`
- `src/lib/streams/types.ts`
- `src/lib/streams/resolve.ts`

Harbor is MIT licensed. This project keeps its own source layout and ports protocol behavior rather than embedding the Windows installation binaries.
