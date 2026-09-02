import Foundation

// MARK: - Stream parser — port of Harbor's TS parser semantics.
// SPEC: docs/audit/stream-engine.md §2 (parsing parity = TS parser side; the
// desktop fast path parses in TS then runs Rust trust/score/rank).
// Every regex follows the audit; [TS≠RUST] divergences take the TS behavior.

enum StreamParser {

    // MARK: - Trusted groups (51 entries, audit §2.14)

    static let trustedGroups: Set<String> = [
        "FRDS", "FRAMESTOR", "FORM", "EVO", "RARBG", "ETHEL", "FLUX", "QXR",
        "MEGUSTA", "ION10", "PSA", "AMIABLE", "GALAXYRG", "WEBDV", "RZEROX",
        "SIC", "TGX", "NTB", "NTG", "TEPES", "GECKOS", "SUCCESSFULCRAB",
        "SUBSPLEASE", "ERAI", "ERAIRAWS", "JUDAS", "ASW", "EMBER", "ANE", "CLEO",
        "BEATRICERAWS", "AKIHITO", "VODES", "NANDESUKA", "SMOL", "TENRAISENSEI",
        "GST", "ANIMEKAIZOKU", "REINFORCE", "RAWS", "OZR", "PURGATORY", "SHK",
        "KOTUWA", "KIRION", "COMMIE", "DAMEDESUYO", "MTBB", "GJM", "SOFCJ",
    ]

    // MARK: - Language tables (exact copies of parser.rs LANG_TOKENS / FLAG_TO_LANGUAGE / ISO_PAIR_TO_LANGUAGE)

    static let langTokens: [String: String] = [
        "ENG": "English", "ENGLISH": "English",
        "ITA": "Italian", "ITALIAN": "Italian",
        "RUS": "Russian", "RUSSIAN": "Russian",
        "HIN": "Hindi", "HINDI": "Hindi",
        "ESP": "Spanish", "SPA": "Spanish", "SPANISH": "Spanish",
        "LAT": "Spanish (Latin America)", "LATINO": "Spanish (Latin America)",
        "LATAM": "Spanish (Latin America)", "CASTELLANO": "Spanish",
        "KOR": "Korean", "KOREAN": "Korean",
        "JPN": "Japanese", "JAPANESE": "Japanese", "JAP": "Japanese",
        "CHN": "Chinese", "CHI": "Chinese", "CHINESE": "Chinese",
        "ZHO": "Chinese", "MAN": "Chinese", "MANDARIN": "Chinese",
        "CANTONESE": "Chinese",
        "POR": "Portuguese", "PORTUGUESE": "Portuguese",
        "PTBR": "Portuguese", "DUBLADO": "Portuguese",
        "GER": "German", "GERMAN": "German", "DEU": "German",
        "FRA": "French", "FRENCH": "French", "FRE": "French",
        "VFF": "French", "VFQ": "French", "VOSTFR": "French",
        "TUR": "Turkish", "TURKISH": "Turkish",
        "ARA": "Arabic", "ARABIC": "Arabic",
        "TAM": "Tamil", "TAMIL": "Tamil",
        "TEL": "Telugu", "TELUGU": "Telugu",
        "CES": "Czech", "CZECH": "Czech", "CZE": "Czech",
        "DAN": "Danish", "DANISH": "Danish",
        "FIN": "Finnish", "FINNISH": "Finnish",
        "HEB": "Hebrew", "HEBREW": "Hebrew",
        "HUN": "Hungarian", "HUNGARIAN": "Hungarian",
        "NLD": "Dutch", "DUTCH": "Dutch", "DUT": "Dutch",
        "NOR": "Norwegian", "NORWEGIAN": "Norwegian",
        "POL": "Polish", "POLISH": "Polish",
        "RON": "Romanian", "ROMANIAN": "Romanian", "ROM": "Romanian",
        "SWE": "Swedish", "SWEDISH": "Swedish",
        "THA": "Thai", "THAI": "Thai",
        "UKR": "Ukrainian", "UKRAINIAN": "Ukrainian",
        "VIE": "Vietnamese", "VIETNAMESE": "Vietnamese",
    ]

    static let flagToLanguage: [String: String] = [
        "US": "English", "GB": "English", "CA": "English", "AU": "English",
        "NZ": "English", "IE": "English",
        "ES": "Spanish", "MX": "Spanish", "AR": "Spanish", "CO": "Spanish",
        "PE": "Spanish", "CL": "Spanish",
        "IT": "Italian",
        "DE": "German", "AT": "German", "CH": "German",
        "FR": "French", "BE": "French", "LU": "French",
        "JP": "Japanese",
        "KR": "Korean", "KP": "Korean",
        "CN": "Chinese", "HK": "Chinese", "TW": "Chinese", "SG": "Chinese",
        "PT": "Portuguese", "BR": "Portuguese",
        "RU": "Russian", "BY": "Russian",
        "IN": "Hindi", "PK": "Hindi",
        "SA": "Arabic", "AE": "Arabic", "EG": "Arabic", "IQ": "Arabic",
        "JO": "Arabic", "KW": "Arabic", "LB": "Arabic", "MA": "Arabic",
        "QA": "Arabic", "SY": "Arabic", "TN": "Arabic",
        "IL": "Hebrew",
        "TR": "Turkish",
        "NL": "Dutch",
        "NO": "Norwegian",
        "PL": "Polish",
        "RO": "Romanian", "MD": "Romanian",
        "SE": "Swedish",
        "DK": "Danish",
        "FI": "Finnish",
        "CZ": "Czech",
        "HU": "Hungarian",
        "TH": "Thai",
        "UA": "Ukrainian",
        "VN": "Vietnamese",
        "GR": "Greek",
        "ID": "Indonesian",
        "MY": "Malay",
        "PH": "Tagalog",
        "IR": "Persian",
    ]

    static let isoPairToLanguage: [String: String] = [
        "EN": "English", "GB": "English", "US": "English", "CA": "English",
        "AU": "English", "NZ": "English",
        "ES": "Spanish", "MX": "Spanish",
        "IT": "Italian",
        "DE": "German",
        "FR": "French",
        "PT": "Portuguese", "BR": "Portuguese",
        "RU": "Russian",
        "JA": "Japanese", "JP": "Japanese",
        "KO": "Korean", "KR": "Korean",
        "ZH": "Chinese", "CN": "Chinese", "TW": "Chinese", "HK": "Chinese",
        "HI": "Hindi",
        "AR": "Arabic", "SA": "Arabic", "AE": "Arabic", "EG": "Arabic",
        "TR": "Turkish",
        "NL": "Dutch",
        "PL": "Polish",
        "RO": "Romanian",
        "SV": "Swedish", "SE": "Swedish",
        "DA": "Danish",
        "FI": "Finnish",
        "CS": "Czech", "CZ": "Czech",
        "HU": "Hungarian",
        "TH": "Thai",
        "UK": "Ukrainian", "UA": "Ukrainian",
        "VI": "Vietnamese",
        "IL": "Hebrew", "HE": "Hebrew",
        "GR": "Greek",
        "ID": "Indonesian",
        "MY": "Malay",
        "PH": "Tagalog",
        "IR": "Persian", "FA": "Persian",
    ]

    // MARK: - Regexes (precompiled)

    private static let qualityTokenRX = try! NSRegularExpression(
        pattern: "4k|uhd|2160p|1080p|720p|480p|sd|hd|hdr|dv", options: [.caseInsensitive])
    private static let yearRX = try! NSRegularExpression(pattern: "\\b(?:19|20)\\d{2}\\b")
    private static let resolutionRXRaw = try! NSRegularExpression(pattern: "([0-9]{3,4}[pi])", options: [.caseInsensitive])
    private static let extendedRX = try! NSRegularExpression(pattern: "EXTENDED(?:[\\s.]CUT)?", options: [.caseInsensitive])
    private static let theatricalRX = try! NSRegularExpression(pattern: "Theatrical(?:[. ]Cut)?", options: [.caseInsensitive])
    private static let uncutRX = try! NSRegularExpression(pattern: ".+\\bUNCUT\\b", options: [.caseInsensitive])
    private static let openMatteRX = try! NSRegularExpression(pattern: "OPEN[. ]MATTE", options: [.caseInsensitive])
    private static let hardcodedRXRaw = try! NSRegularExpression(pattern: "HC|HARDCODED|HARDSUB", options: [.caseInsensitive])
    private static let properRX = try! NSRegularExpression(pattern: "\\b(?:REAL.)?PROPER\\b", options: [.caseInsensitive])
    private static let repackRX = try! NSRegularExpression(pattern: "REPACK|RERIP", options: [.caseInsensitive])
    private static let remasteredRX = try! NSRegularExpression(pattern: "\\bRemaster(?:ed)?\\b", options: [.caseInsensitive])
    private static let unratedRX = try! NSRegularExpression(pattern: "\\bunrated|uncensored\\b", options: [.caseInsensitive])
    private static let criterionRX = try! NSRegularExpression(pattern: "\\bCriterion\\b", options: [.caseInsensitive])
    private static let codecHevcRX = try! NSRegularExpression(pattern: "h[-. ]?265|hevc", options: [.caseInsensitive])
    private static let codecAvcRX = try! NSRegularExpression(pattern: "h[-. ]?264|avc", options: [.caseInsensitive])
    private static let codecLegacyRX = try! NSRegularExpression(pattern: "dvix|mpeg2|divx|xvid|x[-. ]?26[45]", options: [.caseInsensitive])
    private static let channelsNumericRX = try! NSRegularExpression(pattern: "\\d+[.\\s](?:1|0)\\b")
    private static let bitDepthRX = try! NSRegularExpression(pattern: "\\b(8|10|12|16|24)[-\\s.]?bits?\\b", options: [.caseInsensitive])
    private static let groupRX = try! NSRegularExpression(
        pattern: "-[ \\(\\[]*(?:\\w+[ \\]\\)]+)?(\\w+(?:\\.\\w+)?)[\\)\\]]?(?:\\.(?:mkv|mp4))?$")
    private static let seasonPackTextRX = try! NSRegularExpression(
        pattern: "\\b(complete|season[\\s\\.]?pack|s\\d{1,2}\\b(?!e))\\b", options: [.caseInsensitive])
    private static let animeHashRX = try! NSRegularExpression(pattern: "\\[([0-9A-Fa-f]{8})\\]")
    private static let sizeRX = try! NSRegularExpression(
        pattern: "(\\d+(?:\\.\\d+)?)\\s*(GB|MB|TB|GiB|MiB|TiB)\\b", options: [.caseInsensitive])
    private static let seedersRX = try! NSRegularExpression(
        pattern: "(?:👥|👤|S:|seeds?:?|\\bS\\s*=\\s*)\\s*(\\d+)", options: [.caseInsensitive])
    private static let containerRX = try! NSRegularExpression(
        pattern: "\\.(mkv|mp4|m4v|avi|webm|mov|ts|wmv)\\b", options: [.caseInsensitive])
    private static let episodeTitleAnchorRX = try! NSRegularExpression(
        pattern: "S(\\d{1,2})E(\\d{1,3})", options: [.caseInsensitive])
    private static let yearRangeRX = try! NSRegularExpression(pattern: "\\b(19\\d\\d|20\\d\\d)[\\-\\.](19\\d\\d|20\\d\\d)\\b")
    private static let discRX = try! NSRegularExpression(pattern: "\\bDISC\\s*(\\d+)\\b", options: [.caseInsensitive])
    private static let repackIterRX = try! NSRegularExpression(pattern: "\\bREPACK(\\d+)?\\b", options: [.caseInsensitive])
    private static let remuxTextRX = try! NSRegularExpression(pattern: "\\bRemux\\b", options: [.caseInsensitive])
    private static let editionTextRX = try! NSRegularExpression(
        pattern: "\\b(IMAX|EXTENDED|DIRECTORS?[.\\s]?CUT|THEATRICAL|UNRATED|UNCUT|REMASTERED|RESTORATION|CRITERION|OPEN[.\\s]?MATTE|HYBRID)\\b",
        options: [.caseInsensitive])

    // MARK: - Main entry

    static func parse(_ stream: EngineStream) -> ParsedStream {
        let filenameLine = extractFilenameLine(stream)
        let fullText = [filenameLine, stream.title, stream.description, stream.name]
            .compactMap { $0 }
            .joined(separator: " ")

        let titleInfo = parseTitleInfo(filenameLine ?? fullText)
        let resolutionRaw = detectResolutionRaw(fullText, titleInfo: titleInfo)
        let resolution = mapResolution(resolutionRaw)
        let hdr = detectHDR(fullText)
        let codec = mapCodec(titleInfo.codecRaw ?? detectCodecRaw(fullText))
        let source = detectSource(fullText)
        let audioCodec = detectAudio(fullText)
        var channels = detectChannels(fullText) ?? titleInfo.channels
        channels = channels ?? 2
        var bitDepth = detectBitDepth(fullText)
        if bitDepth == nil { bitDepth = titleInfo.bitDepth }
        let languages = parseLanguages(fullText)
        let size = detectSize(fullText, stream: stream)
        let seeders = detectSeeders(fullText)
        let container = detectContainer(stream: stream, filenameLine: filenameLine, fullText: fullText)

        let edition = parseEdition(fullText, titleInfo: titleInfo)
        let yearRange = parseYearRange(fullText)
        let discIndex = parseDiscIndex(fullText)
        let repackIteration = parseRepackIteration(fullText, titleInfo: titleInfo)
        let proper = titleInfo.proper || properRX.matches(fullText)
        let hardcoded = titleInfo.hardcoded || hardcodedRXRaw.matches(fullText)
        let remux = remuxTextRX.matches(fullText)

        let episodeTitle = parseEpisodeTitle(filenameLine ?? fullText)
        let seasonPack = titleInfo.seasonPack || parseSeasonPack(fullText, titleInfo: titleInfo)
        let releaseGroup = titleInfo.group
        let releaseGroupNormalized = releaseGroup.map(normalizeGroup)

        let animeHash = parseAnimeHash(fullText)
        let scamScore = computeScamScore(resolution: resolution, source: source, size: size)
        let cacheFlags = parseCacheFlags(text: fullText, stream: stream)

        return ParsedStream(
            stream: stream,
            parsedTitle: titleInfo.cleanTitle,
            episodeTitle: episodeTitle,
            resolution: resolution,
            hdrFormat: hdr,
            codec: codec,
            source: source,
            audio: AudioInfo(codec: audioCodec, channels: channels, bitDepth: bitDepth),
            audioLanguages: languages,
            size: size,
            seeders: seeders,
            cached: cacheFlags.cached,
            inLibrary: [:],
            container: container,
            releaseGroup: releaseGroup,
            releaseGroupNormalized: releaseGroupNormalized,
            remux: remux,
            edition: edition,
            year: titleInfo.year,
            yearRange: yearRange,
            season: titleInfo.season,
            episode: titleInfo.episode,
            seasonPack: seasonPack,
            discIndex: discIndex,
            repackIteration: repackIteration,
            proper: proper,
            hardcoded: hardcoded,
            animeHash: animeHash,
            scamScore: scamScore
        )
    }

    // MARK: - 2.1 Text assembly + filename score

    static func extractFilenameLine(_ stream: EngineStream) -> String? {
        let candidates = [
            stream.behaviorHints?.effectiveFilename,
            stream.title, stream.description, stream.name,
        ].compactMap { $0 }
        var best: (score: Int, line: String)?
        for raw in candidates {
            for line in raw.components(separatedBy: .newlines) {
                let score = filenameScore(line, addonName: stream.addonName)
                if best == nil || score > best!.score {
                    best = (score, line)
                }
            }
        }
        return best?.line
    }

    static func filenameScore(_ line: String, addonName: String) -> Int {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 8 else { return -100 }
        let addonLower = addonName.lowercased()
        if ["torrentio", "comet", "mediafusion", "aiostreams", "knightcrawler", "jackettio", "torbox"]
            .contains(where: { addonLower.hasPrefix($0) && trimmed.lowercased().hasPrefix($0) }) {
            return -100
        }
        let lower = trimmed.lowercased()
        if qualityTokenRX.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil
            && trimmed.split(separator: " ").count == 1 {
            return -100
        }
        if trimmed.contains("👤") || trimmed.contains("👥") || trimmed.contains("💾") || trimmed.contains("📦") {
            return -100
        }
        if lower.hasPrefix("size:") || lower.hasPrefix("seeds:") || lower.hasPrefix("seeders:")
            || lower.hasPrefix("peers:") || lower.hasPrefix("languages:") {
            return -50
        }
        if lower.hasPrefix("[rd+") || lower.hasPrefix("[tb+") || lower.hasPrefix("[ad+")
            || lower.hasPrefix("[pm+") || lower.hasPrefix("[dl+") {
            return -50
        }
        var score = 0
        if trimmed.count >= 20 { score += 2 }
        if trimmed.filter({ $0 == "." }).count >= 3 { score += 3 }
        if yearRX.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil { score += 2 }
        if resolutionRXRaw.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil { score += 2 }
        if episodeTitleAnchorRX.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil { score += 3 }
        if detectSource(trimmed) != .other { score += 3 }
        if codecHevcRX.matches(trimmed) || codecAvcRX.matches(trimmed) { score += 1 }
        if containerRX.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil { score += 2 }
        if score == 0 && trimmed.filter({ !$0.isLetter && !$0.isNumber }).count == 0 { score -= 20 }
        return score
    }

    // MARK: - 2.2 Title / year / season / episode / group

    struct TitleInfo {
        var cleanTitle: String = ""
        var year: Int?
        var resolutionRaw: String?
        var codecRaw: String?
        var channels: Int?
        var bitDepth: Int?
        var group: String?
        var season: Int?
        var episode: Int?
        var proper = false
        var hardcoded = false
        var extended = false
        var uncut = false
        var theatrical = false
        var openMatte = false
        var remastered = false
        var unrated = false
        var criterion = false
        var repack = false
        var seasonPack = false
    }

    private static func parseTitleInfo(_ text: String) -> TitleInfo {
        var info = TitleInfo()
        var working = text

        info.extended = extendedRX.matches(working)
        info.theatrical = theatricalRX.matches(working)
        info.uncut = uncutRX.matches(working)
        info.openMatte = openMatteRX.matches(working)
        info.hardcoded = hardcodedRXRaw.matches(working)
        info.proper = properRX.matches(working)
        info.remastered = remasteredRX.matches(working)
        info.unrated = unratedRX.matches(working)
        info.criterion = criterionRX.matches(working)

        // Year (first capture).
        if let match = yearRX.firstMatch(in: working, range: NSRange(working.startIndex..., in: working)),
           match.numberOfRanges > 0 {
            let value = (working as NSString).substring(with: match.range(at: 0))
            info.year = Int(value)
        }

        // Resolution raw.
        if let match = resolutionRXRaw.firstMatch(in: working, range: NSRange(working.startIndex..., in: working)),
           match.numberOfRanges > 1 {
            info.resolutionRaw = (working as NSString).substring(with: match.range(at: 1))
        } else if working.range(of: "\\b4k\\b", options: [.regularExpression, .caseInsensitive]) != nil {
            info.resolutionRaw = "4k"
        } else if working.range(of: "FHD|\\b1080\\b", options: [.regularExpression, .caseInsensitive]) != nil {
            info.resolutionRaw = "1080p"
        } else if working.range(of: "\\bUHD\\b", options: [.regularExpression, .caseInsensitive]) != nil {
            info.resolutionRaw = "4k"
        }

        // Codec raw.
        if codecHevcRX.matches(working) {
            info.codecRaw = "h265"
        } else if codecAvcRX.matches(working) {
            info.codecRaw = "h264"
        } else if codecLegacyRX.matches(working) {
            info.codecRaw = "xvid"
        }

        // Channels.
        if let match = channelsNumericRX.firstMatch(in: working, range: NSRange(working.startIndex..., in: working)) {
            let value = (working as NSString).substring(with: match.range(at: 0))
            info.channels = parseChannelsValue(value)
        }

        // Bit depth.
        if let match = bitDepthRX.firstMatch(in: working, range: NSRange(working.startIndex..., in: working)),
           match.numberOfRanges > 1 {
            info.bitDepth = Int((working as NSString).substring(with: match.range(at: 1)))
        }

        // Season (first match wins).
        if let match = firstMatch(seasonPatterns, working) {
            info.season = match.season
            info.episode = match.episode
            if match.episode == nil { info.seasonPack = true }
        }

        // Group.
        if let match = groupRX.firstMatch(in: working, range: NSRange(working.startIndex..., in: working)),
           match.numberOfRanges > 1 {
            info.group = (working as NSString).substring(with: match.range(at: 1))
        }

        // Clean title.
        info.cleanTitle = cleanTitle(working)
        return info
    }

    private static func parseChannelsValue(_ raw: String) -> Int? {
        if raw.contains(".") || raw.contains(" ") {
            let cleaned = raw.replacingOccurrences(of: " ", with: ".")
            return Int(cleaned.prefix(1)) == nil ? nil : Int(cleaned.split(separator: ".").first ?? "0")
        }
        return nil
    }

    private static let seasonPackPatterns = try! NSRegularExpression(
        pattern: "([0-9]{1,2})xall|S([0-9]{1,2}) ?E[0-9]{1,2}|([0-9]{1,2})x[0-9]{1,2}|(?:Saison|Season)[. _-]?([0-9]{1,2})|\\bS([0-9]{1,2})(?![0-9])",
        options: [.caseInsensitive])

    private static func firstMatch(_ regex: NSRegularExpression, _ text: String) -> (season: Int?, episode: Int?)? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        let ns = text as NSString
        // Season group: 1, 2, 3, 4, 5 depending on branch. Episode groups: 2/3 (SxxEyy / xx×yy) or absent.
        var season: Int?
        var episode: Int?
        for group in 1..<match.numberOfRanges {
            let range = match.range(at: group)
            guard range.location != NSNotFound else { continue }
            let value = ns.substring(with: range)
            guard let number = Int(value) else { continue }
            if season == nil {
                season = number
            } else if episode == nil, group <= 3 {
                episode = number
            }
        }
        return (season, episode)
    }

    // Season/episode with explicit first-match-wins ordering (audit §2.2).
    private static let seasonPatterns = try! NSRegularExpression(
        pattern: "([0-9]{1,2})xall|S([0-9]{1,2}) ?E[0-9]{1,2}|([0-9]{1,2})x[0-9]{1,2}|(?:Saison|Season)[. _-]?([0-9]{1,2})|\\bS([0-9]{1,2})(?![0-9])",
        options: [.caseInsensitive])

    private static let seasonRXs: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: "([0-9]{1,2})xall", options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: "S([0-9]{1,2}) ?E([0-9]{1,5})", options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: "([0-9]{1,2})x([0-9]{1,5})", options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: "(?:Saison|Season)[. _-]?([0-9]{1,2})", options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: "\\bS([0-9]{1,2})(?![0-9])", options: [.caseInsensitive]),
    ]

    private static func firstMatch(_ regexes: [NSRegularExpression], _ text: String) -> (season: Int?, episode: Int?)? {
        for regex in regexes {
            guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { continue }
            let ns = text as NSString
            var season: Int?
            var episode: Int?
            if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
                season = Int(ns.substring(with: match.range(at: 1)))
            }
            if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
                episode = Int(ns.substring(with: match.range(at: 2)))
            }
            return (season, episode)
        }
        return nil
    }

    private static func cleanTitle(_ working: String) -> String {
        var title = working
        // Cut at season/episode markers and quality tokens.
        if let range = title.range(of: "S\\d{1,2}E\\d{1,3}", options: .regularExpression) {
            title = String(title[..<range.lowerBound])
        } else if let range = title.range(of: "\\d{1,2}x\\d{1,3}", options: .regularExpression) {
            title = String(title[..<range.lowerBound])
        }
        // Cut at quality stop tokens.
        if let range = title.range(of: "(1080p|720p|480p|2160p|4k|UHD|HDR|DV|WEB-DL|WEBRip|BluRay|BDRip|HDRip|DVDRip|HDTV|REMUX|REMUX|HDTS|HDCAM|CAM|TS|TC|SCR|PROPER|REPACK)", options: [.regularExpression, .caseInsensitive]) {
            title = String(title[..<range.lowerBound])
        }
        // Cut at year.
        if let range = title.range(of: "\\b(?:19|20)\\d{2}\\b", options: .regularExpression) {
            title = String(title[..<range.lowerBound])
        }
        // Cut at release group.
        if let match = groupRX.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
           match.numberOfRanges > 1 {
            let groupRange = match.range(at: 1)
            if groupRange.location != NSNotFound {
                title = (title as NSString).substring(to: groupRange.location)
            }
        }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: ". _-"))
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
        if title.hasSuffix("- ") { title.removeLast(2) }
        return title.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - 2.3–2.7 resolution / HDR / codec / source / audio

    static func mapResolution(_ raw: String?) -> Resolution {
        guard let raw else { return .sd }
        let value = raw.lowercased()
        if value.contains("2160") || value == "4k" || value == "uhd" { return .uhd }
        if value.contains("1080") { return .p1080 }
        if value.contains("720") { return .p720 }
        if value.contains("480") { return .p480 }
        return .sd
    }

    private static func detectResolutionRaw(_ text: String, titleInfo: TitleInfo) -> String? {
        titleInfo.resolutionRaw ?? {
            if text.range(of: "\\b4k\\b", options: [.regularExpression, .caseInsensitive]) != nil { return "4k" }
            if text.range(of: "FHD|\\b1080\\b", options: [.regularExpression, .caseInsensitive]) != nil { return "1080p" }
            if text.range(of: "\\bUHD\\b", options: [.regularExpression, .caseInsensitive]) != nil { return "4k" }
            return nil
        }()
    }

    private static let dvHdr10RX = try! NSRegularExpression(pattern: "\\bDV[+\\-\\s.]?HDR10\\+?\\b|\\bDoVi[+\\-\\s.]?HDR10\\+?\\b|\\bDolby[\\.\\s]?Vision[+\\-\\s.]?HDR10\\+?\\b", options: [.caseInsensitive])
    private static let dvRX = try! NSRegularExpression(pattern: "\\bDV\\b|\\bDoVi\\b|\\bDolby[\\.\\s]?Vision\\b", options: [.caseInsensitive])
    private static let hdr10PlusRX = try! NSRegularExpression(pattern: "\\bHDR10\\+\\b", options: [.caseInsensitive])
    private static let hlgRX = try! NSRegularExpression(pattern: "\\bHLG\\b", options: [.caseInsensitive])
    private static let hdr10RX = try! NSRegularExpression(pattern: "\\bHDR10?\\b|\\bHDR\\b", options: [.caseInsensitive])

    static func detectHDR(_ text: String) -> HdrFormat? {
        if dvHdr10RX.matches(text) { return .dvHdr10 }
        if dvRX.matches(text) { return .dv }
        if hdr10PlusRX.matches(text) { return .hdr10Plus }
        if hlgRX.matches(text) { return .hlg }
        if hdr10RX.matches(text) { return .hdr10 }
        return nil
    }

    private static func detectCodecRaw(_ text: String) -> String? {
        if codecHevcRX.matches(text) { return "h265" }
        if codecAvcRX.matches(text) { return "h264" }
        if codecLegacyRX.matches(text) { return "xvid" }
        return nil
    }

    static func mapCodec(_ raw: String?) -> Codec {
        guard let raw else { return .other }
        let value = raw.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ".", with: "").replacingOccurrences(of: "-", with: "")
        if value.contains("265") || value == "hevc" { return .hevc }
        if value.contains("264") || value == "avc" { return .avc }
        if value.contains("av1") { return .av1 }
        if value.contains("vp9") { return .vp9 }
        if value.contains("mpeg") { return .mpeg2 }
        return .other
    }

    // Source detection — 14 ordered rules including TS-only extras (audit §2.6).
    private static let sourceRules: [(NSRegularExpression, Source)] = [
        (try! NSRegularExpression(pattern: "\\bHC[\\s._\\-]?(?:HDRip|HD[\\s._\\-]?Rip|CAM(?:Rip)?)\\b", options: [.caseInsensitive]), .cam),
        (try! NSRegularExpression(pattern: "\\b(?:HD|Clean|New|HQ|TS)[\\s._\\-]?CAM(?:Rip)?\\b|\\bCAM(?:Rip)?\\b", options: [.caseInsensitive]), .cam),
        (try! NSRegularExpression(pattern: "\\bHD[\\s._\\-]?TS\\b|\\bHDTS\\b", options: [.caseInsensitive]), .hdts),
        (try! NSRegularExpression(pattern: "\\bTELESYNC\\b|\\bTS[\\s._\\-]?Rip\\b|\\bPDVDRip\\b|\\bTS\\b(?=[\\s._\\-]\\d{3,4}[pi]\\b)|(?<=\\b(?:19|20)\\d{2}[\\s._\\-])TS\\b", options: [.caseInsensitive]), .ts),
        (try! NSRegularExpression(pattern: "\\bTELECINE\\b|\\bHD[\\s._\\-]?TC\\b|\\bTC\\b(?=[\\s._\\-]\\d{3,4}[pi]\\b)|(?<=\\b(?:19|20)\\d{2}[\\s._\\-])TC\\b", options: [.caseInsensitive]), .tc),
        (try! NSRegularExpression(pattern: "\\bSCREENER\\b|\\bDVDSCR\\b|\\bDVDScreener\\b|\\bBDSCR\\b|\\bWEB[\\s._\\-]?SCR\\b|\\bSCR\\b", options: [.caseInsensitive]), .scr),
        (try! NSRegularExpression(pattern: "\\bRemux\\b", options: [.caseInsensitive]), .remux),
        (try! NSRegularExpression(pattern: "\\bBluRay\\b|\\bBDRip\\b|\\bBRRip\\b", options: [.caseInsensitive]), .bluRay),
        (try! NSRegularExpression(pattern: "\\bWEB[\\.\\-]?DL\\b", options: [.caseInsensitive]), .webDl),
        (try! NSRegularExpression(pattern: "\\bWEBRip\\b|\\bWEB-Rip\\b", options: [.caseInsensitive]), .webRip),
        (try! NSRegularExpression(pattern: "\\bHDRip\\b", options: [.caseInsensitive]), .hdRip),
        (try! NSRegularExpression(pattern: "\\bDVDRip\\b", options: [.caseInsensitive]), .dvdRip),
        (try! NSRegularExpression(pattern: "\\bHDTV\\b", options: [.caseInsensitive]), .hdtv),
        (try! NSRegularExpression(pattern: "\\bWEB\\b", options: [.caseInsensitive]), .webDl),   // TS-only fallback
    ]

    static func detectSource(_ text: String) -> Source {
        for (regex, source) in sourceRules where regex.matches(text) {
            return source
        }
        return .other
    }

    // Audio — 9 ordered rules (audit §2.7).
    private static let audioRules: [(NSRegularExpression, AudioCodec)] = [
        (try! NSRegularExpression(pattern: "\\bAtmos\\b", options: [.caseInsensitive]), .atmos),
        (try! NSRegularExpression(pattern: "\\bTrueHD\\b", options: [.caseInsensitive]), .trueHD),
        (try! NSRegularExpression(pattern: "\\bDTS-HD\\.?MA\\b|\\bDTS\\.?HD\\.?MA\\b", options: [.caseInsensitive]), .dtsHdMa),
        (try! NSRegularExpression(pattern: "\\bDTS\\b", options: [.caseInsensitive]), .dts),
        (try! NSRegularExpression(pattern: "\\bDDP?5?\\.?1\\+?\\b|\\bE-?AC3\\b|\\bDD\\+\\b", options: [.caseInsensitive]), .ddPlus),
        (try! NSRegularExpression(pattern: "\\bAC3\\b", options: [.caseInsensitive]), .ac3),
        (try! NSRegularExpression(pattern: "\\bAAC\\b", options: [.caseInsensitive]), .aac),
        (try! NSRegularExpression(pattern: "\\bFLAC\\b", options: [.caseInsensitive]), .flac),
        (try! NSRegularExpression(pattern: "\\bOpus\\b", options: [.caseInsensitive]), .opus),
    ]

    static func detectAudio(_ text: String) -> AudioCodec {
        for (regex, codec) in audioRules where regex.matches(text) {
            return codec
        }
        return .other
    }

    private static let channelsTextRX = try! NSRegularExpression(pattern: "\\b(7\\.1|5\\.1|6\\.1|2\\.1|2\\.0)\\b")

    static func detectChannels(_ text: String) -> Int? {
        guard let match = channelsTextRX.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1 else { return nil }
        let value = (text as NSString).substring(with: match.range(at: 1))
        switch value {
        case "7.1": return 8
        case "6.1": return 7
        case "5.1": return 6
        case "2.1": return 3
        case "2.0": return 2
        default: return 2
        }
    }

    private static let bitDepthTextRX = try! NSRegularExpression(pattern: "\\b(8|10|12)\\s*bit\\b", options: [.caseInsensitive])

    static func detectBitDepth(_ text: String) -> Int? {
        guard let match = bitDepthTextRX.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1 else { return nil }
        return Int((text as NSString).substring(with: match.range(at: 1)))
    }

    // MARK: - 2.9 languages

    static let langTokenRX = try! NSRegularExpression(
        pattern: "\\b(ENG|ENGLISH|ITA|ITALIAN|RUS|RUSSIAN|HIN|HINDI|ESP|SPA|SPANISH|LAT|LATINO|LATAM|CASTELLANO|KOR|KOREAN|JPN|JAPANESE|JAP|CHN|CHI|CHINESE|ZHO|MAN|MANDARIN|CANTONESE|POR|PORTUGUESE|PTBR|DUBLADO|GER|GERMAN|DEU|FRA|FRENCH|FRE|VFF|VFQ|VOSTFR|TUR|TURKISH|ARA|ARABIC|TAM|TAMIL|TEL|TELUGU|CES|CZECH|CZE|DAN|DANISH|FIN|FINNISH|HEB|HEBREW|HUN|HUNGARIAN|NLD|DUTCH|DUT|NOR|NORWEGIAN|POL|POLISH|RON|ROMANIAN|ROM|SWE|SWEDISH|THA|THAI|UKR|UKRAINIAN|VIE|VIETNAMESE|MULTI|DUAL)\\b",
        options: [.caseInsensitive])
    static let flagRX = try! NSRegularExpression(pattern: "[🇺🇸-🇿🇼]{2}")
    static let isoPairRX = try! NSRegularExpression(
        pattern: "\\b(EN|GB|US|CA|AU|NZ|ES|MX|IT|DE|FR|PT|BR|RU|JA|JP|KO|KR|ZH|CN|TW|HK|HI|AR|SA|AE|EG|TR|NL|PL|RO|SV|SE|DA|FI|CS|CZ|HU|TH|UK|UA|VI|IL|HE|GR|ID|MY|PH|IR|FA)\\b")

    static func parseLanguages(_ text: String) -> [String] {
        var seenMulti = false
        var languages: [String] = []

        // 1. Word tokens.
        for match in matches(langTokenRX, in: text) {
            let token = match.uppercased()
            if token == "MULTI" || token == "DUAL" {
                seenMulti = true
            } else if let language = langTokens[token], !languages.contains(language) {
                languages.append(language)
            }
        }
        // 2. Flag emoji.
        for match in matches(flagRX, in: text) {
            let code = regionalCode(from: match)
            if let language = flagToLanguage[code], !languages.contains(language) {
                languages.append(language)
            }
        }
        // 3. ISO pairs.
        for match in matches(isoPairRX, in: text) {
            let code = match.uppercased()
            if let language = isoPairToLanguage[code], !languages.contains(language) {
                languages.append(language)
            }
        }

        if languages.count > 1 {
            return ["Multi"] + languages
        }
        if languages.count == 1 {
            return languages
        }
        if seenMulti {
            return ["Multi"]
        }
        return []
    }

    private static func regionalCode(from flag: String) -> String {
        let scalars = flag.unicodeScalars
        guard scalars.count == 2 else { return "" }
        let base: UInt32 = 0x1F1E6
        let first = scalars[scalars.startIndex].value
        let second = scalars[scalars.index(scalars.startIndex, offsetBy: 1)].value
        let a = Character(UnicodeScalar(65 + (first - base))!)
        let b = Character(UnicodeScalar(65 + (second - base))!)
        return String([a, b])
    }

    // MARK: - 2.10 size / seeders / container

    static func parseSize(_ text: String) -> UInt64? {
        guard let match = sizeRX.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 2 else { return nil }
        let valueString = (text as NSString).substring(with: match.range(at: 1))
        let unit = (text as NSString).substring(with: match.range(at: 2)).lowercased()
        guard let value = Double(valueString) else { return nil }
        switch unit {
        case "tb", "tib": return UInt64(value * 1024 * 1024 * 1024 * 1024)
        case "gb", "gib": return UInt64(value * 1024 * 1024 * 1024)
        case "mb", "mib": return UInt64(value * 1024 * 1024)
        default: return nil
        }
    }

    static func detectSize(_ text: String, stream: EngineStream) -> UInt64? {
        if let videoSize = stream.behaviorHints?.videoSize, videoSize > 0 {
            return UInt64(videoSize)
        }
        return parseSize(text)
    }

    static func parseSeeders(_ text: String) -> UInt32? {
        guard let match = seedersRX.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1 else { return nil }
        return UInt32((text as NSString).substring(with: match.range(at: 1)))
    }

    static func detectSeeders(_ text: String) -> UInt32? {
        parseSeeders(text)
    }

    static func detectContainer(stream: EngineStream, filenameLine: String?, fullText: String) -> Container? {
        let searchOrder = [stream.behaviorHints?.effectiveFilename, filenameLine, fullText].compactMap { $0 }
        for text in searchOrder {
            guard let match = containerRX.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  match.numberOfRanges > 1 else { continue }
            let value = (text as NSString).substring(with: match.range(at: 1)).lowercased()
            switch value {
            case "mkv": return .mkv
            case "mp4": return .mp4
            case "m4v": return .m4v
            case "avi": return .avi
            case "webm": return .webm
            case "mov": return .mov
            case "ts": return .ts
            case "wmv": return .wmv
            default: continue
            }
        }
        return nil
    }

    // MARK: - 2.11 edition / year range / disc / repack

    static func parseEdition(_ text: String, titleInfo: TitleInfo) -> String? {
        // ptt priority order.
        if titleInfo.extended { return "Extended" }
        if titleInfo.unrated { return "Unrated" }
        if titleInfo.theatrical { return "Theatrical" }
        if titleInfo.uncut { return "Uncut" }
        if titleInfo.remastered { return "Remastered" }
        if titleInfo.criterion { return "Criterion" }
        if titleInfo.openMatte { return "Open Matte" }
        // Text fallback.
        guard let match = editionTextRX.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1 else { return nil }
        let value = (text as NSString).substring(with: match.range(at: 1))
        return value.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ")
    }

    static func parseYearRange(_ text: String) -> YearRange? {
        guard let match = yearRangeRX.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 2 else { return nil }
        let ns = text as NSString
        guard let first = Int(ns.substring(with: match.range(at: 1))),
              let second = Int(ns.substring(with: match.range(at: 2))) else { return nil }
        let diff = abs(second - first)
        guard diff > 0, diff < 30 else { return nil }
        return YearRange(start: first, end: second)
    }

    static func parseDiscIndex(_ text: String) -> Int? {
        guard let match = discRX.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1 else { return nil }
        return Int((text as NSString).substring(with: match.range(at: 1)))
    }

    static func parseRepackIteration(_ text: String, titleInfo: TitleInfo) -> Int {
        if let match = repackIterRX.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
                return Int((text as NSString).substring(with: match.range(at: 1))) ?? 1
            }
            return 1
        }
        if titleInfo.repack { return 1 }
        return 0
    }

    // MARK: - 2.12 episode title / 2.13 season pack / 2.14 group

    private static let qualityStopRX = try! NSRegularExpression(
        pattern: "\\.(?:2160p|1080p|720p|480p|4K|UHD|HDR|DV|DoVi|WEB-DL|WEBRip|BluRay|BDRip|HDRip|DVDRip|HDTV|REMUX|PROPER|REPACK|HDTS|HDCAM|CAM|TS|TC|SCR|x264|x265|HEVC|H265|AAC|AC3|DD5|DDP5|TRUEHD|ATMOS|DTS)",
        options: [.caseInsensitive])

    static func parseEpisodeTitle(_ filenameLine: String) -> String? {
        guard let match = episodeTitleAnchorRX.firstMatch(in: filenameLine, range: NSRange(filenameLine.startIndex..., in: filenameLine)) else {
            return nil
        }
        let after = (filenameLine as NSString).substring(from: match.range(at: 0).location + match.range(at: 0).length)
        var text = after.trimmingCharacters(in: CharacterSet(charactersIn: ".-_ "))
        if let range = text.range(of: qualityStopRX.pattern, options: .regularExpression) {
            text = String(text[..<range.lowerBound])
        }
        text = text.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ")
            .split(separator: " ").joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard text.count >= 2, text.count <= 80,
              !["episode", "hdtv", "webrip"].contains(text.lowercased()),
              text.lowercased().range(of: "^e\\d+$", options: .regularExpression) == nil else {
            return nil
        }
        return text
    }

    static func parseSeasonPack(_ text: String, titleInfo: TitleInfo) -> Bool {
        if titleInfo.seasonPack { return true }
        guard let match = seasonPackTextRX.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return false
        }
        let ns = text as NSString
        let value = ns.substring(with: match.range(at: 0)).lowercased()
        if value == "complete" || value.contains("season") { return true }
        if value.hasPrefix("s"), value.range(of: "e", options: .caseInsensitive) == nil { return true }
        return false
    }

    static func normalizeGroup(_ group: String) -> String {
        group.uppercased().unicodeScalars
            .filter { ($0.value >= 65 && $0.value <= 90) || ($0.value >= 48 && $0.value <= 57) }
            .map { String(Character($0)) }
            .joined()
    }

    // MARK: - 2.15 anime hash / 2.16 scam score

    static func parseAnimeHash(_ text: String) -> String? {
        guard let match = animeHashRX.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1 else { return nil }
        return (text as NSString).substring(with: match.range(at: 1)).uppercased()
    }

    static func computeScamScore(resolution: Resolution, source: Source, size: UInt64?) -> Int {
        var score = 0
        if let size {
            switch resolution {
            case .uhd where size < 5 * 1024 * 1024 * 1024: score += 3
            case .p1080 where size < 700 * 1024 * 1024: score += 3
            case .p720 where size < 250 * 1024 * 1024: score += 3
            case .sd where size < 250 * 1024 * 1024: score += 3
            default: break
            }
        }
        if resolution == .sd && source == .other {
            score += 2
        }
        return min(score, 8)
    }

    // MARK: - 2.17 cache flags (two-phase: deny first, then cached)

    struct CacheFlagResult {
        var cached: [String: Bool] = [:]
        var uncached: [String: Bool] = [:]
    }

    private static let invisiblesRX = try! NSRegularExpression(pattern: "[\u{200B}-\u{200D}\u{2060}\u{FEFF}]")
    private static let variationSelectorRX = try! NSRegularExpression(pattern: "\u{FE0F}")

    private static let uncachedBracketRX = try! NSRegularExpression(
        pattern: "\\[(RD|TB|AD|PM|DL)(?:[\\s\\-]?download|⬇️?|⏳)\\]", options: [.caseInsensitive])
    private static let cachedBracketRX = try! NSRegularExpression(
        pattern: "\\[(RD|TB|AD|PM|DL)[+⚡]\\]", options: [.caseInsensitive])
    private static let jackettioBareRX = try! NSRegularExpression(
        pattern: "\\[(RD|TB|AD|PM|DL|OC|ED|Putio)\\]\\s+(?:Jackettio|jackettio)\\b", options: [.caseInsensitive])
    private static let streamfusionDownloadRX = try! NSRegularExpression(
        pattern: "^⬇️?download\\n([^\\n]+)")
    private static let streamfusionInstantRX = try! NSRegularExpression(
        pattern: "^⚡instant\\n([^\\n]+)")
    private static let genericUncachedRX = try! NSRegularExpression(
        pattern: "(?:⏳|⬇️?|🔻|❌)\\s*(need cache|download via|not ready|uncached on)?\\s*<service>", options: [.caseInsensitive])
    private static let genericCachedRX = try! NSRegularExpression(
        pattern: "(?:⚡️?|✅)\\s*(cached on|instant on|ready on)?\\s*<service>", options: [.caseInsensitive])
    private static let aiostreamsPrismRX = try! NSRegularExpression(
        pattern: "❌\\s*Not Ready", options: [.caseInsensitive])
    private static let aiostreamsGdriveRX = try! NSRegularExpression(pattern: "🎟️")
    private static let mediafusionUncachedRX = try! NSRegularExpression(
        pattern: "\\b(SVC)\\s*[⏳⬇🔻❌]", options: [.caseInsensitive])
    private static let mediafusionCachedRX = try! NSRegularExpression(
        pattern: "\\b(SVC)\\s*[+⚡✅]", options: [.caseInsensitive])
    private static let aiostreamsInstantRX = try! NSRegularExpression(
        pattern: "(Instant\\b)|⚡\\s*Ready|🎫", options: [.caseInsensitive])
    private static let aiostreamsGenericUncachedRX = try! NSRegularExpression(
        pattern: "☁|UNCACHED", options: [.caseInsensitive])
    private static let aiostreamsGenericCachedRX = try! NSRegularExpression(
        pattern: "[🚀🌩📫]|\\bcached\\b", options: [.caseInsensitive])
    private static let elfhostedCachedRX = try! NSRegularExpression(
        pattern: "\\belf[\\s\\-_]?cache\\b|cached\\s+on\\s+elfhosted", options: [.caseInsensitive])

    private static let debridHostnames = [
        "real-debrid.com", "alldebrid.com", "premiumize.me", "debrid-link.com",
        "torbox.app", "easynews.com", "put.io", "offcloud.com", "easydebrid.com",
    ]

    static func parseCacheFlags(text: String, stream: EngineStream) -> CacheFlagResult {
        var result = CacheFlagResult()
        var cleaned = text
        cleaned = invisiblesRX.stringByReplacingMatches(in: cleaned, options: [], range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
        cleaned = variationSelectorRX.stringByReplacingMatches(in: cleaned, options: [], range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")

        let addonName = stream.addonName.lowercased()
        let addonId = stream.addonId.lowercased()

        // Phase 1 — deny.
        for match in matchObjects(uncachedBracketRX, in: cleaned) {
            if match.numberOfRanges > 1 {
                let slug = (cleaned as NSString).substring(with: match.range(at: 1)).lowercased()
                result.uncached[slug] = true
            }
        }
        for match in matchObjects(jackettioBareRX, in: cleaned) {
            if match.numberOfRanges > 1 {
                let slug = (cleaned as NSString).substring(with: match.range(at: 1)).lowercased()
                result.uncached[slug] = true
            }
        }
        if let match = streamfusionDownloadRX.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           match.numberOfRanges > 1 {
            let serviceLine = (cleaned as NSString).substring(with: match.range(at: 1))
            applyServiceLine(serviceLine, to: &result, cached: false)
        }
        if aiostreamsPrismRX.matches(cleaned) || aiostreamsGdriveRX.matches(cleaned) {
            applyTemplateUncached(stream: stream, addonName: addonName, to: &result)
        }
        if mediafusionUncachedRX.matches(cleaned) {
            result.uncached["rd"] = true   // MediaFusion SVC markers are RD-scoped
        }
        // AIOStreams generic uncached (TS-only).
        if addonName.contains("aiostreams"), aiostreamsGenericUncachedRX.matches(cleaned) {
            applyTemplateUncached(stream: stream, addonName: addonName, to: &result)
        }

        // Phase 2 — cached (never overrides deny).
        for match in matchObjects(cachedBracketRX, in: cleaned) {
            if match.numberOfRanges > 1 {
                let slug = (cleaned as NSString).substring(with: match.range(at: 1)).lowercased()
                if result.uncached[slug] != true { result.cached[slug] = true }
            }
        }
        if let match = streamfusionInstantRX.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           match.numberOfRanges > 1 {
            let serviceLine = (cleaned as NSString).substring(with: match.range(at: 1))
            applyServiceLine(serviceLine, to: &result, cached: true)
        }
        if aiostreamsInstantRX.matches(cleaned) {
            applyTemplateCached(stream: stream, addonName: addonName, to: &result)
        }
        if mediafusionCachedRX.matches(cleaned) {
            if result.uncached["rd"] != true { result.cached["rd"] = true }
        }
        // AIOStreams generic cached (TS-only).
        if addonName.contains("aiostreams"), aiostreamsGenericCachedRX.matches(cleaned) {
            applyTemplateCached(stream: stream, addonName: addonName, to: &result)
        }
        // ElfHosted rule (TS-only): url or addon name matches elfhosted + cache text.
        let isElfHosted = (stream.url?.lowercased().contains("elfhosted") == true) || addonName.contains("elfhosted")
        if isElfHosted, elfhostedCachedRX.matches(cleaned) {
            for slug in ["rd", "tb", "ad", "pm", "dl"] where result.uncached[slug] != true {
                result.cached[slug] = true
            }
        }
        // HTTP-URL heuristic: debrid hostname or known template addon → addon-name slug cached.
        if let url = stream.url?.lowercased(),
           url.hasPrefix("http://") || url.hasPrefix("https://") {
            let host = URL(string: url)?.host?.lowercased() ?? ""
            let isDebridHost = debridHostnames.contains { host == $0 || host.hasSuffix("." + $0) }
            let isTemplateAddon = ["mediafusion", "comet", "torrentio", "aiostreams", "knightcrawler", "jackettio", "streamfusion", "easynews"].contains { addonName.contains($0) }
            if isDebridHost || isTemplateAddon {
                let slug = slugForAddon(addonName: addonName)
                if result.uncached[slug] != true { result.cached[slug] = true }
            }
        }
        return result
    }

    private static func applyServiceLine(_ line: String, to result: inout CacheFlagResult, cached: Bool) {
        let lower = line.lowercased()
        for (slug, names) in serviceSlugNames {
            if names.contains(where: { lower.contains($0) }) {
                if cached {
                    if result.uncached[slug] != true { result.cached[slug] = true }
                } else {
                    result.uncached[slug] = true
                }
            }
        }
    }

    private static let serviceSlugNames: [(String, [String])] = [
        ("rd", ["real-debrid", "real debrid"]),
        ("tb", ["torbox", "tor box"]),
        ("ad", ["alldebrid", "all debrid"]),
        ("pm", ["premiumize"]),
        ("dl", ["debrid-link", "debrid link"]),
    ]

    private static func slugForAddon(addonName: String) -> String {
        if addonName.contains("torbox") { return "tb" }
        if addonName.contains("alldebrid") { return "ad" }
        if addonName.contains("premiumize") { return "pm" }
        if addonName.contains("debrid-link") { return "dl" }
        return "rd"
    }

    private static func applyTemplateCached(stream: EngineStream, addonName: String, to result: inout CacheFlagResult) {
        let slug = slugForAddon(addonName: addonName)
        if result.uncached[slug] != true { result.cached[slug] = true }
    }

    private static func applyTemplateUncached(stream: EngineStream, addonName: String, to result: inout CacheFlagResult) {
        let slug = slugForAddon(addonName: addonName)
        result.uncached[slug] = true
    }

    // MARK: - Regex helpers

    private static func matches(_ regex: NSRegularExpression, in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { (text as NSString).substring(with: $0.range) }
    }

    /// Full match objects (for cache-flag loops that read capture groups).
    private static func matchObjects(_ regex: NSRegularExpression, in text: String) -> [NSTextCheckingResult] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}

private extension NSRegularExpression {
    func matches(_ text: String) -> Bool {
        firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
