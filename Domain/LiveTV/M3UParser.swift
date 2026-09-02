import Foundation

// MARK: - M3U playlist parser (Phase 13, audit live-tv-dvr.md §1.3 — exact port).
// BOM strip, CRLF split, #EXTM3U ignored, #EXTINF/#EXTGRP(sticky)/#EXTVLCOPT/#KODIPROP,
// quote-aware attribute tokenizer, URL pipe-options, decorative-row filtering.

struct M3UChannel: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var tvgId: String?
    var displayName: String
    var title: String
    var logo: String?
    var groupTitle: String?
    var url: String
    var attributes: [String: String]
    var vlcoptUserAgent: String?
    var vlcoptReferrer: String?
    var cookie: String?
    var kodipropLicenseType: String?
    var kodipropLicenseKey: String?

    init(
        id: String, tvgId: String? = nil, displayName: String, title: String,
        logo: String? = nil, groupTitle: String? = nil, url: String,
        attributes: [String: String] = [:], vlcoptUserAgent: String? = nil,
        vlcoptReferrer: String? = nil, cookie: String? = nil,
        kodipropLicenseType: String? = nil, kodipropLicenseKey: String? = nil
    ) {
        self.id = id
        self.tvgId = tvgId
        self.displayName = displayName
        self.title = title
        self.logo = logo
        self.groupTitle = groupTitle
        self.url = url
        self.attributes = attributes
        self.vlcoptUserAgent = vlcoptUserAgent
        self.vlcoptReferrer = vlcoptReferrer
        self.cookie = cookie
        self.kodipropLicenseType = kodipropLicenseType
        self.kodipropLicenseKey = kodipropLicenseKey
    }
}

enum M3UParser {

    // MARK: - EXTINF attribute tokenizer (quote-aware, Harbor parity)

    /// Splits an EXTINF attribute string into {key: value} + duration + title.
    /// Duration = first unquoted token. Title = text after the first comma that
    /// follows the last closing quote (Harbor's attrTitleSplit/firstUnquotedComma).
    static func parseExtinfAttributes(_ raw: String) -> (duration: Double?, attributes: [String: String], title: String) {
        var attributes: [String: String] = [:]
        var duration: Double?
        var title = ""

        var tokens = [String]()
        var current = ""
        var inQuotes = false
        for char in raw {
            if char == "\"" {
                inQuotes.toggle()
                current.append(char)
            } else if char.isWhitespace && !inQuotes {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty { tokens.append(current) }

        var index = 0
        // First unquoted token = duration.
        if index < tokens.count, let first = Double(tokens[index]) {
            duration = first
            index += 1
        }
        // key=value pairs (values may span quoted tokens; even-count quote closing).
        var pendingKey: String?
        var pendingValue = ""
        while index < tokens.count {
            let token = tokens[index]
            if pendingKey == nil, let eq = token.firstIndex(of: "=") {
                pendingKey = String(token[..<eq]).lowercased()
                pendingValue = String(token[eq...].dropFirst())
                // Handle quoted value spanning tokens.
                while pendingValue.filter({ $0 == "\"" }).count % 2 != 0, index + 1 < tokens.count {
                    index += 1
                    pendingValue += " " + tokens[index]
                }
                let clean = pendingValue.replacingOccurrences(of: "\"", with: "")
                attributes[pendingKey!] = clean
                pendingKey = nil
                pendingValue = ""
            } else if pendingKey != nil {
                pendingValue += " " + token
                if pendingValue.filter({ $0 == "\"" }).count % 2 == 0 {
                    attributes[pendingKey!] = pendingValue.replacingOccurrences(of: "\"", with: "")
                    pendingKey = nil
                    pendingValue = ""
                }
            }
            index += 1
        }
        // Title = after the first comma following the last closing quote.
        if let comma = raw.firstIndex(of: ",") {
            title = String(raw[raw.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
        }
        return (duration, attributes, title)
    }

    // MARK: - Decorative-row filters (Harbor parity: parse-time + display-time)

    /// Symbol-only names (m3u.ts isDecorativeRow).
    static func isDecorativeRow(_ name: String) -> Bool {
        guard !name.isEmpty else { return true }
        let symbolRatio = Double(name.filter { !$0.isLetter && !$0.isNumber }.count) / Double(name.count)
        return symbolRatio > 0.8
    }

    /// Divider rows: >55% box-drawing/ASCII symbols (divider-filter.ts).
    static func isDividerChannel(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let symbols = name.filter { char in
            let scalars = char.unicodeScalars
            return scalars.contains { $0.value >= 0x2500 && $0.value <= 0x257F }   // box drawing
                || "═║╔╗╚╝╠╣╦╩╬■□▲▼►◄·•–—―|-=*_~^".contains(char)
        }
        return Double(symbols.count) / Double(name.count) > 0.55
    }

    // MARK: - Main parser

    static func parse(_ content: String, baseId: String) -> [M3UChannel] {
        var text = content
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")

        var channels: [M3UChannel] = []
        var pending: (attributes: [String: String], duration: Double?, title: String)?
        var stickyGroup: String?
        var vlcoptUserAgent: String?
        var vlcoptReferrer: String?
        var kodipropLicenseType: String?
        var kodipropLicenseKey: String?
        var cookie: String?

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#EXTM3U") { continue }

            if line.hasPrefix("#EXTGRP:") {
                stickyGroup = String(line.dropFirst("#EXTGRP:".count)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("#EXTVLCOPT:") {
                let value = String(line.dropFirst("#EXTVLCOPT:".count)).trimmingCharacters(in: .whitespaces)
                if value.lowercased().hasPrefix("http-user-agent=") {
                    vlcoptUserAgent = String(value.dropFirst("http-user-agent=".count))
                } else if value.lowercased().hasPrefix("http-referrer=") {
                    vlcoptReferrer = String(value.dropFirst("http-referrer=".count))
                }
                continue
            }
            if line.hasPrefix("#KODIPROP:") {
                let value = String(line.dropFirst("#KODIPROP:".count))
                if value.lowercased().hasPrefix("inputstream.adaptive.license_type=") {
                    kodipropLicenseType = String(value.dropFirst("inputstream.adaptive.license_type=".count))
                } else if value.lowercased().hasPrefix("inputstream.adaptive.license_key=") {
                    kodipropLicenseKey = String(value.dropFirst("inputstream.adaptive.license_key=".count))
                }
                continue
            }
            if line.hasPrefix("#EXTINF:") {
                let raw = String(line.dropFirst("#EXTINF:".count))
                let (duration, attributes, title) = parseExtinfAttributes(raw)
                pending = (attributes, duration, title)
                continue
            }
            if line.hasPrefix("#") { continue }   // unknown directive ignored (Harbor parity)

            // URL line (with pipe options: url|user-agent=...&referer=...).
            guard var pending else { continue }
            var url = line
            var pipeOptions: [String: String] = [:]
            if let pipe = line.firstIndex(of: "|") {
                url = String(line[..<pipe])
                let opts = String(line[line.index(after: pipe)...])
                for pair in opts.split(separator: "&") {
                    let kv = pair.split(separator: "=", maxSplits: 1)
                    if kv.count == 2 {
                        pipeOptions[String(kv[0]).lowercased()] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                    }
                }
            }

            let attrs = pending.attributes
            let group = attrs["group-title"] ?? stickyGroup
            let tvgName = attrs["tvg-name"]
            let tvgId = attrs["tvg-id"] ?? attrs["tvg-chno"]
            let title = attrs["tvg-name"] ?? pending.title
            let displayName = tvgName ?? (pending.title.isEmpty ? "Channel \(channels.count + 1)" : pending.title)
            let logo = attrs["tvg-logo"] ?? attrs["logo"]

            let idPart = tvgId ?? tvgName ?? (pending.title.isEmpty ? "ch-\(channels.count + 1)" : pending.title)
            let channelID = "\(baseId)::\(idPart)::\(channels.count)"

            // Decorative rows dropped at parse time (Harbor parity).
            guard !isDecorativeRow(displayName) else { continue }

            channels.append(M3UChannel(
                id: channelID,
                tvgId: tvgId,
                displayName: displayName,
                title: title,
                logo: logo,
                groupTitle: group,
                url: url,
                attributes: attrs,
                vlcoptUserAgent: pipeOptions["user-agent"] ?? vlcoptUserAgent,
                vlcoptReferrer: pipeOptions["referer"] ?? pipeOptions["referrer"] ?? vlcoptReferrer,
                cookie: pipeOptions["cookie"].flatMap { cookie == nil ? $0 : cookie } ?? cookie,
                kodipropLicenseType: kodipropLicenseType,
                kodipropLicenseKey: kodipropLicenseKey
            ))

            pending = nil
        }
        return channels
    }

    // MARK: - EPG URL derivation (m3u.ts deriveEpgUrls)

    /// For get.php/player_api.php URLs with credentials, derive the XMLTV URLs.
    static func deriveEpgUrls(playlistURL: String) -> [String] {
        guard let url = URL(string: playlistURL),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let username = queryItems.first(where: { $0.name == "username" })?.value,
              let password = queryItems.first(where: { $0.name == "password" })?.value,
              let origin = components.host.flatMap({ "\(components.scheme ?? "http")://\($0)" }) else {
            return []
        }
        let lastPath = url.lastPathComponent
        guard lastPath == "get.php" || lastPath == "player_api.php" else { return [] }
        var out: [String] = []
        out.append("\(origin)/xmltv.php?username=\(username)&password=\(password)")
        out.append("\(origin)/get.php?username=\(username)&password=\(password)&type=epg")
        return out
    }
}
