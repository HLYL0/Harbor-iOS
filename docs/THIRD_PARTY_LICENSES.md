# Third Party Licenses

> Initial inventory. Update whenever a new dependency lands. Full texts live with each dependency; this file records obligations.

## Direct runtime dependencies (Harbor-iOS)

| Component | License | Notes |
|---|---|---|
| MPVKit (NuvioMedia fork) | LGPL (libmpv), build scripts per-repo | libmpv embedding — see below |
| Apple frameworks (SwiftUI, AVFoundation, Metal, Keychain) | Apple system | no redistribution |
| Swift standard library | Apache 2.0 w/ runtime exception | |

## libmpv / LGPL obligations

- libmpv is LGPLv2.1+ (mpv core is GPL/LGPL mixed; the libmpv library interface is LGPL).
- Sideload/jailbreak distribution: dynamically linking against a library is acceptable under LGPL; **static linking requires offering relinkable object files or LGPL source**. MPVKit builds libmpv as a dynamic framework — keep it that way and do not statically fold it into the app binary.
- No mpv source modifications planned; if any are made, they must be published under the same license.

## The Harbor reference (harborstremio/harbor)

- License: **MIT**.
- We port *behavior and protocol knowledge*, not source files; where code is ported/adapted (e.g. parser rule sets), attribute per MIT terms in the file header and here.
- Harbor's MIT text: https://github.com/harborstremio/harbor/blob/main/LICENSE

## Stremio protocol / addons

- Stremio addon protocol is an open specification; addon manifests/APIs are accessed over HTTPS per addon's own terms.
- Community addons remain user-installed; Harbor-iOS ships no hard-coded third-party content sources (Cinemeta-style official catalogs are accessed as Stremio's own services).

## Fonts / assets

- Harbor's bundled fonts (if any are copied): verify each font's license (OFL etc.) before inclusion; do not copy assets wholesale — replace with licensed equivalents.

## Trademarks

- "Harbor" name/icon usage: per Harbor's MIT + branding; our app identifies itself as an independent client ("Harbor for iOS" community build). Do not imply official endorsement by the Stremio/Harbor projects.
