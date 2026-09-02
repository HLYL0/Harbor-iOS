import Foundation

// MARK: - Deep link parser (spec §71, audit stremio-addons.md §6).
// Validates every incoming stremio:// / harbor:// URL against the allowlist.
// No arbitrary navigation, no scheme-triggered auth.

enum DeepLinkDestination: Equatable, Sendable {
    case detail(type: String, id: String, videoId: String?)
    case addonInstall(manifestURL: URL)
    case watchTogether(relay: String, room: String)

    static func == (lhs: DeepLinkDestination, rhs: DeepLinkDestination) -> Bool {
        switch (lhs, rhs) {
        case (.detail(let t1, let i1, let v1), .detail(let t2, let i2, let v2)):
            return t1 == t2 && i1 == i2 && v1 == v2
        case (.addonInstall(let u1), .addonInstall(let u2)):
            return u1 == u2
        case (.watchTogether(let r1, let c1), .watchTogether(let r2, let c2)):
            return r1 == r2 && c1 == c2
        default:
            return false
        }
    }
}

enum DeepLinkParser {

    static let allowedDetailTypes: Set<String> = ["movie", "series", "channel", "tv", "anime"]

    static func parse(_ rawURL: String) -> DeepLinkDestination? {
        guard let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["stremio", "harbor", "https"].contains(scheme) else {
            return nil
        }

        // stremio://detail/<type>/<id>[/<videoId>] or stremio.com/#/detail/... (Harbor's two shapes)
        if scheme == "stremio" {
            let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            if parts.first == "detail", parts.count >= 3 {
                let type = parts[1].lowercased()
                guard allowedDetailTypes.contains(type) else { return nil }
                let id = parts[2]
                let videoId = parts.count >= 4 ? parts[3] : nil
                return .detail(type: type, id: id, videoId: videoId)
            }
            if url.host == "detail" {
                let rest = parts.filter { $0 != "detail" }
                if rest.count >= 2, allowedDetailTypes.contains(rest[0].lowercased()) {
                    return .detail(type: rest[0].lowercased(), id: rest[1], videoId: rest.count >= 3 ? rest[2] : nil)
                }
            }
            return nil
        }

        // harbor://install?manifest=... or any URL whose path ends in manifest.json (Harbor's forward rule)
        if scheme == "harbor", url.host == "install",
           let manifest = URLComponents(url: url, resolvingAgainstBaseURL: false)?
               .queryItems?.first(where: { $0.name == "manifest" })?.value,
           let manifestURL = URL(string: manifest),
           manifestURL.scheme == "https" {
            return .addonInstall(manifestURL: manifestURL)
        }

        // Watch-together invite: app.harbor.site/?harbor-relay=wss://...&harbor-room=CODE
        if scheme == "https",
           ["app.harbor.site", "app.harborstremio.com"].contains(url.host?.lowercased() ?? "") {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let relay = items.first(where: { $0.name == "harbor-relay" })?.value
            let room = items.first(where: { $0.name == "harbor-room" })?.value
            if let relay, let room, relay.hasPrefix("wss://"), room.range(of: #"^[A-Z0-9]{4,8}$"#, options: .regularExpression) != nil {
                return .watchTogether(relay: relay, room: room)
            }
        }

        // Plain https manifest.json → addon install (Harbor's `contains("manifest.json")` rule).
        if scheme == "https", url.path.hasSuffix("manifest.json") {
            return .addonInstall(manifestURL: url)
        }

        return nil
    }
}
