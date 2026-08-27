import Foundation

enum StremioEndpoint {
    private static let cinemetaBase = URL(string: "https://v3-cinemeta.strem.io")!
    static let accountAPI = URL(string: "https://api.strem.io/api")!

    static func normalizeManifestURL(_ rawValue: String) -> URL? {
        var raw = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        if raw.lowercased().hasPrefix("stremio://") {
            raw = "https://" + String(raw.dropFirst("stremio://".count))
        } else if !raw.contains("://") {
            raw = "https://" + raw
        }

        guard var components = URLComponents(string: raw),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil else {
            return nil
        }

        let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedPath.isEmpty {
            components.path = "/manifest.json"
        } else if !trimmedPath.lowercased().hasSuffix("manifest.json") {
            components.path = "/\(trimmedPath)/manifest.json"
        }
        return components.url
    }

    static func manifestBaseURL(_ manifestURL: URL) -> URL? {
        guard var components = URLComponents(url: manifestURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil else {
            return nil
        }
        var parts = components.path.split(separator: "/").map(String.init)
        guard parts.last?.lowercased() == "manifest.json" else { return nil }
        parts.removeLast()
        components.path = parts.isEmpty ? "" : "/" + parts.joined(separator: "/")
        return components.url
    }

    static func streamURL(manifestURL: URL, type: String, id: String) -> URL? {
        guard var url = manifestBaseURL(manifestURL) else { return nil }
        url.append(path: "stream")
        url.append(path: type)
        url.append(path: id)
        url.appendPathExtension("json")
        return url
    }

    static func cinemetaCatalog(type: String, skip: Int = 0, search: String? = nil) -> URL {
        var url = cinemetaBase
        url.append(path: "catalog")
        url.append(path: type)
        url.append(path: "top")
        if let search, !search.isEmpty {
            url.append(path: "search=\(search)")
        } else if skip > 0 {
            url.append(path: "skip=\(skip)")
        }
        url.appendPathExtension("json")
        return url
    }

    static func cinemetaMeta(type: String, id: String) -> URL {
        var url = cinemetaBase
        url.append(path: "meta")
        url.append(path: type)
        url.append(path: id)
        url.appendPathExtension("json")
        return url
    }
}
