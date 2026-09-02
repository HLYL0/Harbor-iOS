import Foundation

// MARK: - Catch-up URL builder (Phase 13, audit live-tv-dvr.md §3 — EXACT port).
// Five detection paths (attrs → catchupSource → Xtream live-URL regex) and the
// exact transformations for flussonic / xtream / template / utc-lutc fallback.

enum CatchupType: String, Sendable {
    case `default`, append, shift, flussonic, xtream
}

enum CatchupBuilder {

    static let xtreamLiveRegex = try! NSRegularExpression(
        pattern: "^(https?:\\/\\/[^/]+)\\/(?:live\\/)?([^/]+)\\/([^/]+)\\/(\\d+)\\.(\\w+)(?:\\?|$)",
        options: [.caseInsensitive]
    )

    // MARK: - Detection (detectCatchupType)

    static func detectCatchupType(channel: M3UChannel) -> CatchupType {
        let attrs = channel.attributes
        let catchup = (attrs["catchup"] ?? attrs["catchup-type"])?.lowercased() ?? ""
        let catchupSource = attrs["catchup-source"]

        if catchup.contains("flussonic") || catchup == "fs" {
            return .flussonic
        }
        if catchup.contains("xc") || catchup.contains("xtream") {
            return .xtream
        }
        if catchup == "append" {
            return .append
        }
        if catchup == "shift" || catchup == "timeshift" {
            return .shift
        }
        if catchup == "default" || (catchupSource?.isEmpty == false) {
            return .default
        }
        // Xtream live URL auto-detection.
        if let url = URL(string: channel.url),
           xtreamLiveRegex.firstMatch(in: channel.url, range: NSRange(channel.url.startIndex..., in: channel.url)) != nil {
            return .xtream
        }
        return .default
    }

    static func hasCatchup(channel: M3UChannel) -> Bool {
        let attrs = channel.attributes
        if attrs["catchup"] != nil || attrs["catchup-type"] != nil || attrs["catchup-source"] != nil {
            return true
        }
        return detectCatchupType(channel: channel) == .xtream
    }

    // MARK: - URL construction (buildCatchupUrl)

    static func buildCatchupUrl(
        channel: M3UChannel,
        startMs: Int64,
        endMs: Int64,
        nowMs: Int64
    ) -> String? {
        let start = Double(startMs) / 1000
        let end = Double(endMs) / 1000
        let now = Double(nowMs) / 1000
        let duration = max(60, end - start)   // Harbor: duration = max(60, end − start), floored to seconds
        let startFloor = floor(start)
        let nowFloor = floor(now)

        let type = detectCatchupType(channel: channel)
        let source = channel.attributes["catchup-source"]

        switch type {
        case .flussonic:
            return buildFlussonic(channel: channel, start: Int(startFloor), duration: Int(duration))
        case .xtream:
            return buildXtream(channel: channel, startMs: startMs, durationSeconds: Int(duration))
        case .default, .append, .shift:
            if let source, !source.isEmpty {
                // Template-fill an absolute source, or append it to the channel URL.
                if source.hasPrefix("http://") || source.hasPrefix("https://") {
                    return fillTemplate(
                        source,
                        start: startFloor, end: floor(end), now: nowFloor, duration: Int(duration)
                    )
                }
                let separator = channel.url.contains("?") ? "&" : "?"
                let trimmedSource = source.trimmingCharacters(in: CharacterSet(charactersIn: "?&"))
                return "\(channel.url)\(separator)\(trimmedSource)"
            }
            // Classic utc/lutc shift fallback.
            return "\(channel.url)?utc=\(Int(startFloor))&lutc=\(Int(nowFloor))"
        }
    }

    /// Flussonic: path match /(stem).(m3u8|ts|mpd) → {dir}/{stem}-{start}-{duration}.{ext}
    /// (mpegts/mono → index); no extension → {path}/archive-{start}-{duration}.ts. Query preserved.
    static func buildFlussonic(channel: M3UChannel, start: Int, duration: Int) -> String? {
        guard let url = URL(string: channel.url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let query = components.query.map { "?\($0)" } ?? ""
        let path = url.path
        let pattern = #"^(.*)\/([^\/]+)\.(m3u8|ts|mpd)$"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) {
            let dir = (path as NSString).substring(with: match.range(at: 1))
            var stem = (path as NSString).substring(with: match.range(at: 2))
            let ext = (path as NSString).substring(with: match.range(at: 3)).lowercased()
            if stem == "mpegts" || stem == "mono" { stem = "index" }
            return "\(dir)/\(stem)-\(start)-\(duration).\(ext)\(query)"
        }
        return "\(path)/archive-\(start)-\(duration).ts\(query)"
    }

    /// Xtream: {host}/timeshift/{user}/{pass}/{ceil(dur/60)}/{Y-m-d:H-M UTC of start}/{id}.ts
    static func buildXtream(channel: M3UChannel, startMs: Int64, durationSeconds: Int) -> String? {
        let range = NSRange(channel.url.startIndex..., in: channel.url)
        guard let match = xtreamLiveRegex.firstMatch(in: channel.url, range: range) else { return nil }
        let url = channel.url as NSString
        let host = url.substring(with: match.range(at: 1))
        let user = url.substring(with: match.range(at: 2))
        let pass = url.substring(with: match.range(at: 3))
        let streamId = url.substring(with: match.range(at: 4))
        let minutes = Int(ceil(Double(durationSeconds) / 60))
        let timestamp = utcFormatted(startMs)
        return "\(host)/timeshift/\(user)/\(pass)/\(minutes)/\(timestamp)/\(streamId).ts"
    }

    /// {start}-of-program formatted Y-m-d:H-M in UTC (Xtream timeshift convention).
    static func utcFormatted(_ epochMs: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(epochMs) / 1000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%d-%02d-%02d:%02d-%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!)
    }

    /// Template tokens (Harbor fillTemplate, audit §3.2): case-insensitive, $ optional.
    static func fillTemplate(
        _ template: String,
        start: Double, end: Double, now: Double, duration: Int
    ) -> String {
        var out = template
        let tokens: [(String, String)] = [
            ("${utc:Y}", "%04d"), ("${utc:m}", "%02d"), ("${utc:d}", "%02d"),
            ("${utc:H}", "%02d"), ("${utc:M}", "%02d"), ("${utc:S}", "%02d"),
        ]
        _ = tokens   // strftime handled below via regex
        out = replaceToken("${utc}", value: String(Int(start)), in: out)
        out = replaceToken("{utc}", value: String(Int(start)), in: out)
        out = replaceToken("${timestamp}", value: String(Int(start)), in: out)
        out = replaceToken("{timestamp}", value: String(Int(start)), in: out)
        out = replaceToken("${start}", value: String(Int(start)), in: out)
        out = replaceToken("{start}", value: String(Int(start)), in: out)
        out = replaceToken("${end}", value: String(Int(end)), in: out)
        out = replaceToken("{end}", value: String(Int(end)), in: out)
        out = replaceToken("${utcend}", value: String(Int(end)), in: out)
        out = replaceToken("{utcend}", value: String(Int(end)), in: out)
        out = replaceToken("${now}", value: String(Int(now)), in: out)
        out = replaceToken("{now}", value: String(Int(now)), in: out)
        out = replaceToken("${lutc}", value: String(Int(now)), in: out)
        out = replaceToken("{lutc}", value: String(Int(now)), in: out)
        out = replaceToken("${timenow}", value: String(Int(now)), in: out)
        out = replaceToken("{timenow}", value: String(Int(now)), in: out)
        out = replaceToken("${duration}", value: String(duration), in: out)
        out = replaceToken("{duration}", value: String(duration), in: out)
        out = replaceToken("${dur}", value: String(duration), in: out)
        out = replaceToken("{dur}", value: String(duration), in: out)
        out = replaceToken("${offset}", value: String(Int(now - start)), in: out)
        out = replaceToken("{offset}", value: String(Int(now - start)), in: out)
        out = replaceToken("${duration-minutes}", value: String(Int(ceil(Double(duration) / 60))), in: out)
        out = replaceToken("{duration-minutes}", value: String(Int(ceil(Double(duration) / 60))), in: out)

        // strftime forms ${utc:FMT} / {utc:FMT} with Y m d H M S (UTC, zero-padded).
        out = replaceStrftime(in: out, prefix: "${utc:", start: start)
        out = replaceStrftime(in: out, prefix: "{utc:", start: start)
        out = replaceStrftime(in: out, prefix: "${start:", start: start)
        out = replaceStrftime(in: out, prefix: "{start:", start: start)
        return out
    }

    private static func replaceToken(_ token: String, value: String, in template: String) -> String {
        template.replacingOccurrences(of: token, with: value, options: [.caseInsensitive])
    }

    private static func replaceStrftime(in template: String, prefix: String, start: Double) -> String {
        var out = template
        while let openRange = out.range(of: prefix) {
            let searchStart = openRange.upperBound
            guard let closeRange = out.range(of: "}", range: searchStart..<out.endIndex) else { break }
            let format = String(out[searchStart..<closeRange.lowerBound])
            out.replaceSubrange(openRange.lowerBound..<closeRange.upperBound, with: strftime(format, epochSeconds: start))
        }
        return out
    }

    private static func strftime(_ format: String, epochSeconds: Double) -> String {
        let date = Date(timeIntervalSince1970: epochSeconds)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        var out = ""
        for char in format {
            switch char {
            case "Y": out += String(format: "%04d", c.year ?? 0)
            case "m": out += String(format: "%02d", c.month ?? 0)
            case "d": out += String(format: "%02d", c.day ?? 0)
            case "H": out += String(format: "%02d", c.hour ?? 0)
            case "M": out += String(format: "%02d", c.minute ?? 0)
            case "S": out += String(format: "%02d", c.second ?? 0)
            default: out.append(char)
            }
        }
        return out
    }
}
