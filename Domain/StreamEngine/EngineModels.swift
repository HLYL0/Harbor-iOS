import Foundation

// MARK: - Canonical stream-engine types.
// Mirrors rust/harbor-core/src/types.rs EXACTLY (serde renames preserved) so the
// JSON golden vectors produced by the Rust reference are decodable 1:1.
// Do NOT rename cases or change raw values without updating the vector fixtures.

enum Resolution: String, Codable, CaseIterable, Sendable, Equatable {
    case uhd = "4K"
    case p1080 = "1080p"
    case p720 = "720p"
    case p480 = "480p"
    case sd = "SD"

    static let `default`: Resolution = .sd
}

enum HdrFormat: String, Codable, Sendable, Equatable {
    case hdr10 = "HDR10"
    case hdr10Plus = "HDR10+"
    case dv = "DV"
    case dvHdr10 = "DV+HDR10"
    case hlg = "HLG"
}

enum Codec: String, Codable, Sendable, Equatable {
    case hevc = "HEVC"
    case avc = "AVC"
    case av1 = "AV1"
    case vp9 = "VP9"
    case mpeg2 = "MPEG2"
    case other = "Other"

    static let `default`: Codec = .other
}

enum AudioCodec: String, Codable, Sendable, Equatable {
    case atmos = "Atmos"
    case trueHD = "TrueHD"
    case dtsHdMa = "DTS-HD MA"
    case dts = "DTS"
    case ddPlus = "DD+"
    case ac3 = "AC3"
    case aac = "AAC"
    case opus = "Opus"
    case flac = "FLAC"
    case other = "Other"

    static let `default`: AudioCodec = .other
}

enum Source: String, Codable, CaseIterable, Sendable, Equatable {
    case bluRay = "BluRay"
    case remux = "REMUX"
    case webDl = "WEB-DL"
    case webRip = "WEBRip"
    case bdRip = "BDRip"
    case hdRip = "HDRip"
    case dvdRip = "DVDRip"
    case hdtv = "HDTV"
    case cam = "CAM"
    case ts = "TS"
    case hdts = "HDTS"
    case tc = "TC"
    case scr = "SCR"
    case other = "Other"

    static let `default`: Source = .other
}

enum Tier: String, Codable, Comparable, Sendable, Equatable {
    case uhdDv = "4K_DV"
    case uhdHdr = "4K_HDR"
    case uhd = "4K"
    case p1080Hdr = "1080p_HDR"
    case p1080 = "1080p"
    case p720 = "720p"
    case sd = "SD"
    case rough = "ROUGH"

    /// Harbor's tier ordering: 4K_DV > 4K_HDR > 4K > 1080p_HDR > 1080p > 720p > SD > ROUGH.
    var rank: Int {
        switch self {
        case .uhdDv: return 7
        case .uhdHdr: return 6
        case .uhd: return 5
        case .p1080Hdr: return 4
        case .p1080: return 3
        case .p720: return 2
        case .sd: return 1
        case .rough: return 0
        }
    }

    static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rank < rhs.rank }
}

enum Container: String, Codable, Sendable, Equatable {
    case mkv, mp4, m4v, avi, webm, mov, ts, wmv
}

struct AudioInfo: Codable, Equatable, Sendable {
    var codec: AudioCodec
    var channels: Int
    var bitDepth: Int?

    init(codec: AudioCodec = .other, channels: Int = 2, bitDepth: Int? = nil) {
        self.codec = codec
        self.channels = channels
        self.bitDepth = bitDepth
    }
}

struct Contributor: Codable, Equatable, Sendable {
    var id: String
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Mirrors the Rust `Stream` shape (camelCase).
struct EngineStream: Codable, Equatable, Sendable {
    var name: String?
    var title: String?
    var description: String?
    var infoHash: String?
    var fileIdx: Int64?
    var url: String?
    var ytId: String?
    var externalUrl: String?
    var subtitles: [StreamSubtitle]?
    var behaviorHints: EngineBehaviorHints?
    var sources: [String]?
    var availability: Double?
    var addonId: String
    var addonName: String
    var addonPriority: Int?
    var addonReturnIdx: Int?
    var contributors: [Contributor]?
    /// Rust `Stream.extra` flatten bag (trust-critical: `nzbUrl` playable-source check).
    var extra: [String: String]?

    init(
        name: String? = nil, title: String? = nil, description: String? = nil,
        infoHash: String? = nil, fileIdx: Int64? = nil, url: String? = nil,
        ytId: String? = nil, externalUrl: String? = nil, subtitles: [StreamSubtitle]? = nil,
        behaviorHints: EngineBehaviorHints? = nil, sources: [String]? = nil,
        availability: Double? = nil, addonId: String = "", addonName: String = "",
        addonPriority: Int? = nil, addonReturnIdx: Int? = nil, contributors: [Contributor]? = nil
    ) {
        self.name = name; self.title = title; self.description = description
        self.infoHash = infoHash; self.fileIdx = fileIdx; self.url = url
        self.ytId = ytId; self.externalUrl = externalUrl; self.subtitles = subtitles
        self.behaviorHints = behaviorHints; self.sources = sources
        self.availability = availability; self.addonId = addonId; self.addonName = addonName
        self.addonPriority = addonPriority; self.addonReturnIdx = addonReturnIdx
        self.contributors = contributors
        self.extra = nil
    }
}

/// Subset of behaviorHints the engine consumes (Rust keeps the whole blob; we decode what we use).
struct EngineBehaviorHints: Codable, Equatable, Sendable {
    var filename: String?
    var fileName: String?
    var videoSize: Int64?

    init(filename: String? = nil, fileName: String? = nil, videoSize: Int64? = nil) {
        self.filename = filename
        self.fileName = fileName
        self.videoSize = videoSize
    }

    var effectiveFilename: String? { filename ?? fileName }
}

struct YearRange: Codable, Equatable, Sendable {
    var start: Int
    var end: Int

    init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

struct ParsedStream: Codable, Equatable, Sendable {
    var stream: EngineStream
    var parsedTitle: String
    var episodeTitle: String?
    var resolution: Resolution
    var hdrFormat: HdrFormat?
    var codec: Codec
    var source: Source
    var audio: AudioInfo
    var audioLanguages: [String]
    var size: UInt64?
    var seeders: UInt32?
    var cached: [String: Bool]
    var inLibrary: [String: Bool]
    var container: Container?
    var releaseGroup: String?
    var releaseGroupNormalized: String?
    var remux: Bool
    var edition: String?
    var year: Int?
    var yearRange: YearRange?
    var season: Int?
    var episode: Int?
    var seasonPack: Bool
    var discIndex: Int?
    var repackIteration: Int
    var proper: Bool
    var hardcoded: Bool
    var animeHash: String?
    var scamScore: Int

    init(
        stream: EngineStream = EngineStream(),
        parsedTitle: String = "", episodeTitle: String? = nil,
        resolution: Resolution = .sd, hdrFormat: HdrFormat? = nil,
        codec: Codec = .other, source: Source = .other,
        audio: AudioInfo = AudioInfo(), audioLanguages: [String] = [],
        size: UInt64? = nil, seeders: UInt32? = nil,
        cached: [String: Bool] = [:], inLibrary: [String: Bool] = [:],
        container: Container? = nil, releaseGroup: String? = nil,
        releaseGroupNormalized: String? = nil, remux: Bool = false,
        edition: String? = nil, year: Int? = nil, yearRange: YearRange? = nil,
        season: Int? = nil, episode: Int? = nil, seasonPack: Bool = false,
        discIndex: Int? = nil, repackIteration: Int = 0, proper: Bool = false,
        hardcoded: Bool = false, animeHash: String? = nil, scamScore: Int = 0
    ) {
        self.stream = stream; self.parsedTitle = parsedTitle; self.episodeTitle = episodeTitle
        self.resolution = resolution; self.hdrFormat = hdrFormat; self.codec = codec
        self.source = source; self.audio = audio; self.audioLanguages = audioLanguages
        self.size = size; self.seeders = seeders; self.cached = cached; self.inLibrary = inLibrary
        self.container = container; self.releaseGroup = releaseGroup
        self.releaseGroupNormalized = releaseGroupNormalized; self.remux = remux
        self.edition = edition; self.year = year; self.yearRange = yearRange
        self.season = season; self.episode = episode; self.seasonPack = seasonPack
        self.discIndex = discIndex; self.repackIteration = repackIteration
        self.proper = proper; self.hardcoded = hardcoded; self.animeHash = animeHash
        self.scamScore = scamScore
    }
}

// Codable support for yearRange (Rust encodes as [start, end] array).
extension ParsedStream {
    private enum CodingKeys: String, CodingKey {
        case stream, parsedTitle, episodeTitle, resolution, hdrFormat, codec, source
        case audio, audioLanguages, size, seeders, cached, inLibrary, container
        case releaseGroup, releaseGroupNormalized, remux, edition, year, yearRange
        case season, episode, seasonPack, discIndex, repackIteration, proper
        case hardcoded, animeHash, scamScore
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stream = try c.decode(EngineStream.self, forKey: .stream)
        parsedTitle = try c.decodeIfPresent(String.self, forKey: .parsedTitle) ?? ""
        episodeTitle = try c.decodeIfPresent(String.self, forKey: .episodeTitle)
        resolution = try c.decode(Resolution.self, forKey: .resolution)
        hdrFormat = try c.decodeIfPresent(HdrFormat.self, forKey: .hdrFormat)
        codec = try c.decode(Codec.self, forKey: .codec)
        source = try c.decode(Source.self, forKey: .source)
        audio = try c.decode(AudioInfo.self, forKey: .audio)
        audioLanguages = try c.decodeIfPresent([String].self, forKey: .audioLanguages) ?? []
        size = try c.decodeIfPresent(UInt64.self, forKey: .size)
        seeders = try c.decodeIfPresent(UInt32.self, forKey: .seeders)
        cached = try c.decodeIfPresent([String: Bool].self, forKey: .cached) ?? [:]
        inLibrary = try c.decodeIfPresent([String: Bool].self, forKey: .inLibrary) ?? [:]
        container = try c.decodeIfPresent(Container.self, forKey: .container)
        releaseGroup = try c.decodeIfPresent(String.self, forKey: .releaseGroup)
        releaseGroupNormalized = try c.decodeIfPresent(String.self, forKey: .releaseGroupNormalized)
        remux = try c.decodeIfPresent(Bool.self, forKey: .remux) ?? false
        edition = try c.decodeIfPresent(String.self, forKey: .edition)
        year = try c.decodeIfPresent(Int.self, forKey: .year)
        if let arr = try c.decodeIfPresent([Int].self, forKey: .yearRange), arr.count == 2 {
            yearRange = YearRange(start: arr[0], end: arr[1])
        } else { yearRange = nil }
        season = try c.decodeIfPresent(Int.self, forKey: .season)
        episode = try c.decodeIfPresent(Int.self, forKey: .episode)
        seasonPack = try c.decodeIfPresent(Bool.self, forKey: .seasonPack) ?? false
        discIndex = try c.decodeIfPresent(Int.self, forKey: .discIndex)
        repackIteration = try c.decodeIfPresent(Int.self, forKey: .repackIteration) ?? 0
        proper = try c.decodeIfPresent(Bool.self, forKey: .proper) ?? false
        hardcoded = try c.decodeIfPresent(Bool.self, forKey: .hardcoded) ?? false
        animeHash = try c.decodeIfPresent(String.self, forKey: .animeHash)
        scamScore = try c.decodeIfPresent(Int.self, forKey: .scamScore) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(stream, forKey: .stream)
        try c.encode(parsedTitle, forKey: .parsedTitle)
        try c.encodeIfPresent(episodeTitle, forKey: .episodeTitle)
        try c.encode(resolution, forKey: .resolution)
        try c.encodeIfPresent(hdrFormat, forKey: .hdrFormat)
        try c.encode(codec, forKey: .codec)
        try c.encode(source, forKey: .source)
        try c.encode(audio, forKey: .audio)
        try c.encode(audioLanguages, forKey: .audioLanguages)
        try c.encodeIfPresent(size, forKey: .size)
        try c.encodeIfPresent(seeders, forKey: .seeders)
        if !cached.isEmpty { try c.encode(cached, forKey: .cached) }
        if !inLibrary.isEmpty { try c.encode(inLibrary, forKey: .inLibrary) }
        try c.encodeIfPresent(container, forKey: .container)
        try c.encodeIfPresent(releaseGroup, forKey: .releaseGroup)
        try c.encodeIfPresent(releaseGroupNormalized, forKey: .releaseGroupNormalized)
        try c.encode(remux, forKey: .remux)
        try c.encodeIfPresent(edition, forKey: .edition)
        try c.encodeIfPresent(year, forKey: .year)
        if let yearRange { try c.encode([yearRange.start, yearRange.end], forKey: .yearRange) }
        try c.encodeIfPresent(season, forKey: .season)
        try c.encodeIfPresent(episode, forKey: .episode)
        try c.encode(seasonPack, forKey: .seasonPack)
        try c.encodeIfPresent(discIndex, forKey: .discIndex)
        try c.encode(repackIteration, forKey: .repackIteration)
        try c.encode(proper, forKey: .proper)
        try c.encode(hardcoded, forKey: .hardcoded)
        try c.encodeIfPresent(animeHash, forKey: .animeHash)
        try c.encode(scamScore, forKey: .scamScore)
    }
}

struct ScoreReason: Codable, Equatable, Sendable {
    var signal: String
    var delta: Double

    init(signal: String, delta: Double) {
        self.signal = signal
        self.delta = delta
    }
}

struct ScoredStream: Codable, Equatable, Sendable {
    var parsed: ParsedStream
    var score: Double
    var reasons: [ScoreReason]
    var tier: Tier

    init(parsed: ParsedStream, score: Double, reasons: [ScoreReason], tier: Tier) {
        self.parsed = parsed
        self.score = score
        self.reasons = reasons
        self.tier = tier
    }
}

struct RankedPicker: Codable, Equatable, Sendable {
    var primary: ScoredStream?
    var byTier: [String: ScoredStream]
    var all: [ScoredStream]

    init(primary: ScoredStream? = nil, byTier: [String: ScoredStream] = [:], all: [ScoredStream] = []) {
        self.primary = primary
        self.byTier = byTier
        self.all = all
    }
}

struct TrustOptions: Codable, Equatable, Sendable {
    var kind: String?
    var expectedTitle: String?
    var expectedYear: Int?
    var expectedSeason: Int?
    var expectedEpisode: Int?
    var releaseDate: String?
    /// Generator-provided relative day offset; the parity harness re-derives an
    /// absolute releaseDate at replay time so cinema-window fixtures never age out.
    var releaseDateDaysAgo: Int?
    var allowSeasonPacks: Bool
    var allowCam: Bool
    var allowSizeOutliers: Bool
    var strict: Bool
    var disabled: Bool
    var preferredLanguages: [String]
    var preferredAudioLangs: [String]
    var requirePreferredLanguage: Bool
    var isAnime: Bool

    init(
        kind: String? = nil, expectedTitle: String? = nil, expectedYear: Int? = nil,
        expectedSeason: Int? = nil, expectedEpisode: Int? = nil, releaseDate: String? = nil,
        releaseDateDaysAgo: Int? = nil,
        allowSeasonPacks: Bool = false, allowCam: Bool = false, allowSizeOutliers: Bool = false,
        strict: Bool = true, disabled: Bool = false, preferredLanguages: [String] = [],
        preferredAudioLangs: [String] = [], requirePreferredLanguage: Bool = false,
        isAnime: Bool = false
    ) {
        self.kind = kind; self.expectedTitle = expectedTitle; self.expectedYear = expectedYear
        self.expectedSeason = expectedSeason; self.expectedEpisode = expectedEpisode
        self.releaseDate = releaseDate; self.releaseDateDaysAgo = releaseDateDaysAgo
        self.allowSeasonPacks = allowSeasonPacks
        self.allowCam = allowCam; self.allowSizeOutliers = allowSizeOutliers
        self.strict = strict; self.disabled = disabled
        self.preferredLanguages = preferredLanguages
        self.preferredAudioLangs = preferredAudioLangs
        self.requirePreferredLanguage = requirePreferredLanguage
        self.isAnime = isAnime
    }
}

struct Rejection: Codable, Equatable, Sendable {
    var stream: ParsedStream
    var reason: String

    init(stream: ParsedStream, reason: String) {
        self.stream = stream
        self.reason = reason
    }
}

struct ScoreOptions: Codable, Equatable, Sendable {
    var activeDebrids: [String]
    var preferredLanguages: [String]
    var releaseDate: String?
    var mediaKind: String?
    var runtimeMinutes: Int?
    var inTheaters: Bool
    var respectAddonOrder: Bool
    var preferredReleaseGroup: String?
    var bandwidthMbps: Double?
    var preferSingleAudioTrack: Bool
    var preferAddonId: String?

    init(
        activeDebrids: [String] = [], preferredLanguages: [String] = [],
        releaseDate: String? = nil, mediaKind: String? = nil, runtimeMinutes: Int? = nil,
        inTheaters: Bool = false, respectAddonOrder: Bool = false,
        preferredReleaseGroup: String? = nil, bandwidthMbps: Double? = nil,
        preferSingleAudioTrack: Bool = false, preferAddonId: String? = nil
    ) {
        self.activeDebrids = activeDebrids
        self.preferredLanguages = preferredLanguages
        self.releaseDate = releaseDate
        self.mediaKind = mediaKind
        self.runtimeMinutes = runtimeMinutes
        self.inTheaters = inTheaters
        self.respectAddonOrder = respectAddonOrder
        self.preferredReleaseGroup = preferredReleaseGroup
        self.bandwidthMbps = bandwidthMbps
        self.preferSingleAudioTrack = preferSingleAudioTrack
        self.preferAddonId = preferAddonId
    }
}

struct CorpusStats: Codable, Equatable, Sendable {
    var daysSinceRelease: Double?
    var trustedTrackedFraction: Double
    var theaterCaptureFraction: Double
    var webishFraction: Double
    var trustedTrackedCount: Int

    init(
        daysSinceRelease: Double? = nil, trustedTrackedFraction: Double = 0,
        theaterCaptureFraction: Double = 0, webishFraction: Double = 0,
        trustedTrackedCount: Int = 0
    ) {
        self.daysSinceRelease = daysSinceRelease
        self.trustedTrackedFraction = trustedTrackedFraction
        self.theaterCaptureFraction = theaterCaptureFraction
        self.webishFraction = webishFraction
        self.trustedTrackedCount = trustedTrackedCount
    }
}
