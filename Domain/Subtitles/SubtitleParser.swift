import Foundation

// MARK: - Subtitle pipeline (Phase 11, audit player.md §5).
// Parsing: SRT / VTT / ASS (dialogue lines). Encoding normalization ports Harbor's
// prepare_subtitle_download: UTF-8 BOM strip, UTF-16 → UTF-8, legacy encodings with
// windows-1256 (Arabic) before windows-1252. Time shifting: Harbor's applyTimeShift.

struct SubtitleCue: Codable, Equatable, Sendable {
    var startSeconds: Double
    var endSeconds: Double
    var text: String

    init(startSeconds: Double, endSeconds: Double, text: String) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
    }
}

enum SubtitleFormat: String, Sendable {
    case srt, vtt, ass
}

enum SubtitleParser {

    // MARK: - Format detection (Harbor: content sniff before extension fallback)

    static func detectFormat(_ content: String) -> SubtitleFormat {
        if content.hasPrefix("[Script Info]") || content.contains("[Events]") {
            return .ass
        }
        if content.hasPrefix("WEBVTT") {
            return .vtt
        }
        return .srt
    }

    // MARK: - Encoding normalization (Harbor's prepare_subtitle_download port)

    static func decodeNormalized(_ data: Data, hint: SubtitleFormat? = nil) -> String? {
        // UTF-16 BOMs → UTF-8 (Harbor parity).
        if data.count >= 2 {
            let bom = (data[data.startIndex], data[data.startIndex + 1])
            if bom == (0xFF, 0xFE), let s = String(data: data, encoding: .utf16LittleEndian) {
                return stripBom(s)
            }
            if bom == (0xFE, 0xFF), let s = String(data: data, encoding: .utf16BigEndian) {
                return stripBom(s)
            }
        }
        // UTF-8 (with or without BOM).
        if let s = String(data: data, encoding: .utf8) {
            var out = s
            if out.hasPrefix("\u{FEFF}") { out.removeFirst() }
            return out
        }
        // Legacy encodings: Arabic first (windows-1256), then windows-1252 (Harbor order).
        if let s = decodeWindows1256(data) { return s }
        if let s = decodeWindows1252(data) { return s }
        return nil
    }

    static func stripBom(_ string: String) -> String {
        string.hasPrefix("\u{FEFF}") ? String(string.dropFirst()) : string
    }

    static func decodeWindows1256(_ data: Data) -> String? {
        let cfEncoding = CFStringEncoding(CFStringEncodings.windowsArabic.rawValue)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String(data: data, encoding: String.Encoding(rawValue: nsEncoding))
    }

    static func decodeWindows1252(_ data: Data) -> String? {
        let cfEncoding = CFStringEncoding(0x0500)   // kCFStringEncodingWindowsLatin1
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String(data: data, encoding: String.Encoding(rawValue: nsEncoding))
    }

    // MARK: - SRT parsing

    static func parseSRT(_ content: String) -> [SubtitleCue] {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [SubtitleCue] = []
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard lines.count >= 2 else { continue }
            // First non-empty line = index (may be absent in malformed files).
            var cursor = 0
            while cursor < lines.count && lines[cursor].trimmingCharacters(in: .whitespaces).isEmpty { cursor += 1 }
            if cursor < lines.count, Int(lines[cursor].trimmingCharacters(in: .whitespaces)) != nil {
                cursor += 1
            }
            guard cursor < lines.count else { continue }
            let timeLine = lines[cursor]
            guard let (start, end) = parseSRTTimeLine(timeLine) else { continue }
            let text = lines[(cursor + 1)...].joined(separator: "\n")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            cues.append(SubtitleCue(startSeconds: start, endSeconds: end, text: text))
        }
        return cues
    }

    static func parseSRTTimeLine(_ line: String) -> (Double, Double)? {
        // 00:00:01,234 --> 00:00:04,567  (also accepts . instead of ,)
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2,
              let start = parseTimestamp(parts[0].trimmingCharacters(in: .whitespaces)),
              let end = parseTimestamp(parts[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return (start, end)
    }

    /// hh:mm:ss,ms or mm:ss,ms or ss,ms
    static func parseTimestamp(_ raw: String) -> Double? {
        let cleaned = raw.replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.split(separator: ":")
        guard let secondsPart = parts.last, let seconds = Double(secondsPart) else { return nil }
        var total = seconds
        var multiplier = 60.0
        for part in parts.dropLast().reversed() {
            guard let value = Double(part) else { return nil }
            total += value * multiplier
            multiplier *= 60
        }
        return total
    }

    // MARK: - VTT parsing

    static func parseVTT(_ content: String) -> [SubtitleCue] {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var cues: [SubtitleCue] = []
        var index = 0
        // Skip WEBVTT header + metadata.
        while index < lines.count && !lines[index].contains("-->") { index += 1 }
        while index < lines.count {
            let line = lines[index]
            guard line.contains("-->") else { index += 1; continue }
            // Optional cue settings after the end timestamp (e.g. "line:0 position:20%").
            let arrowParts = line.components(separatedBy: "-->")
            guard arrowParts.count == 2 else { index += 1; continue }
            let startRaw = arrowParts[0].trimmingCharacters(in: .whitespaces)
            let endAndSettings = arrowParts[1].trimmingCharacters(in: .whitespaces)
            let endRaw = endAndSettings.split(separator: " ").first.map(String.init) ?? endAndSettings
            // VTT allows hh:mm:ss.mmm (dot) — parseTimestamp handles both.
            guard let start = parseTimestamp(startRaw.replacingOccurrences(of: ",", with: ".")),
                  let end = parseTimestamp(endRaw.replacingOccurrences(of: ",", with: ".")) else {
                index += 1
                continue
            }
            index += 1
            var textLines: [String] = []
            while index < lines.count && !lines[index].contains("-->") && !lines[index].isEmpty {
                textLines.append(lines[index])
                index += 1
            }
            let text = textLines.joined(separator: " ")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)  // strip tags
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            cues.append(SubtitleCue(startSeconds: start, endSeconds: end, text: text))
        }
        return cues
    }

    // MARK: - ASS parsing (dialogue lines; styles parsed by the player backend)

    static func parseASS(_ content: String) -> [SubtitleCue] {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var cues: [SubtitleCue] = []
        for line in normalized.components(separatedBy: "\n") {
            guard line.lowercased().hasPrefix("dialogue:") else { continue }
            var rest = line.dropFirst("dialogue:".count)
            var fields: [String] = []
            for _ in 0..<9 {
                let trimmed = rest.drop(while: { $0 == " " })
                guard let comma = trimmed.firstIndex(of: ",") else { break }
                fields.append(String(trimmed[..<comma]))
                rest = trimmed[comma...].dropFirst()
            }
            guard fields.count >= 9 else { continue }
            let start = parseASSTime(fields[1])
            let end = parseASSTime(fields[2])
            let text = String(rest).trimmingCharacters(in: .whitespaces)
            guard let start, let end else { continue }
            // Strip override tags {…} for plain display (libass renders them on the mpv path).
            let plain = text.replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\N", with: "\n")
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\h", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !plain.isEmpty else { continue }
            cues.append(SubtitleCue(startSeconds: start, endSeconds: end, text: plain))
        }
        return cues
    }

    static func parseASSTime(_ raw: String) -> Double? {
        // h:mm:ss.cc (centiseconds)
        let parts = raw.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }

    // MARK: - Dispatch + time shift

    static func parse(_ content: String, format: SubtitleFormat? = nil) -> [SubtitleCue] {
        switch format ?? detectFormat(content) {
        case .ass: return parseASS(content)
        case .vtt: return parseVTT(content)
        case .srt: return parseSRT(content)
        }
    }

    /// Harbor's applyTimeShift: shift each cue by offsetMs, re-serialize to SRT (audit §5.4).
    static func applyTimeShift(_ cues: [SubtitleCue], offsetMs: Int) -> [SubtitleCue] {
        guard offsetMs != 0 else { return cues }
        let offset = Double(offsetMs) / 1000
        return cues.map { cue in
            SubtitleCue(
                startSeconds: max(0, cue.startSeconds + offset),
                endSeconds: max(0, cue.endSeconds + offset),
                text: cue.text
            )
        }
    }

    static func serializeSRT(_ cues: [SubtitleCue]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(formatSRTTime(cue.startSeconds)) --> \(formatSRTTime(cue.endSeconds))\n\(cue.text.replacingOccurrences(of: "\n", with: " "))\n"
        }.joined(separator: "\n")
    }

    static func formatSRTTime(_ seconds: Double) -> String {
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1) * 1000).rounded())
        let total = Int(seconds)
        return String(format: "%02d:%02d:%02d,%03d", total / 3600, (total % 3600) / 60, total % 60, ms)
    }
}
