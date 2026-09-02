import Foundation

// MARK: - Canonical stream-engine types.
// Mirrors rust/harbor-core/src/types.rs EXACTLY (serde renames preserved) so the
// JSON golden vectors produced by the Rust reference are decodable 1:1.
// Do NOT rename cases or change raw values without updating the vector fixtures.

public enum Resolution: String, Codable, CaseIterable, Sendable, Equatable {
    case uhd = "4K"
    case p1080 = "1080p"
    case p720 = "720p"
    case p480 = "480p"
    case sd = "SD"

    public static let `default`: Resolution = .sd
}

public enum HdrFormat: String, Codable, Sendable, Equatable {
    case hdr10 = "HDR10"
    case hdr10Plus = "HDR10+"
    case dv = "DV"
    case dvHdr10 = "DV+HDR10"
    case hlg = "HLG"
}

public enum Codec: String, Codable, Sendable, Equatable {
    case hevc = "HEVC"
    case avc = "AVC"
    case av1 = "AV1"
    case vp9 = "VP9"
    case mpeg2 = "MPEG2"
    case other = "Other"

    public static let `default`: Codec = .other
}

public enum AudioCodec: String, Codable, Sendable, Equatable {
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

    public static let `default`: AudioCodec = .other
}

public enum Source: String, Codable, CaseIterable, Sendable, Equatable {
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

    public static let `default`: Source = .other
}

public enum Tier: String, Codable, Comparable, Sendable, Equatable {
    case uhdDv = "4K_DV"
    case uhdHdr = "4K_HDR"
    case uhd = "4K"
    case p1080Hdr = "1080p_HDR"
    case p1080 = "1080p"
    case p720 = "720p"
    case sd = "SD"
    case rough = "ROUGH"

    /// Harbor's tier ordering: 4K_DV > 4K_HDR > 4K > 1080p_HDR > 1080p > 720p > SD > ROUGH.
    public var rank: Int {
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

    public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rank < rhs.rank }
}

public enum Container: String, Codable, Sendable, Equatable {
    case mkv, mp4, m4v, avi, webm, mov, ts, wmv
}

public struct AudioInfo: Codable, Equatable, Sendable {
    public var codec: AudioCodec
    public var channels: Int
    public var bitDepth: Int?

    public init(codec: AudioCodec = .other, channels: Int = 2, bitDepth: Int? = nil) {
        self.codec = codec
        self.channels = channels
        self.bitDepth = bitDepth
    }
}

public struct Contributor: Codable, Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Mirrors the Rust `Stream` shape (camelCase).
public struct EngineStream: Codable, Equatable, Sendable {
    public var name: String?
    public var title: String?
    public var description: String?
    public var infoHash: String?
    public var fileIdx: Int64?
    public var url: String?
    public var ytId: String?
    public var externalUrl: String?
    public var subtitles: [StreamSubtitle]?
    public var behaviorHints: EngineBehaviorHints?
    public var sources: [String]?
    public var availability: Double?
    public var addonId: String
    public var addonName: String
    public var addonPriority: Int?
    public var addonReturnIdx: Int?
    public var contributors: [Contributor]?

    public init(
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
    }
}

/// Subset of behaviorHints the engine consumes (Rust keeps the whole blob; we decode what we use).
public struct EngineBehaviorHints: Codable, Equatable, Sendable {
    public var filename: String?
    public var fileName: String?
    public var videoSize: Int64?

    public init(filename: String? = nil, fileName: String? = nil, videoSize: Int64? = nil) {
        self.filename = filename
        self.fileName = fileName
        self.videoSize = videoSize
    }

    public var effectiveFilename: String? { filename ?? fileName }
}

public struct ParsedStream: Codable, Equatable, Sendable {
    public var stream: EngineStream
    public var parsedTitle: String
    public var episodeTitle: String?
    public var resolution: Resolution
    public var hdrFormat: HdrFormat?
    public var codec: Codec
    public var source: Source
    public var audio: AudioInfo
    public var audioLanguages: [String]
    public var size: UInt64?
    public var seeders: UInt32?
    public var cached: [String: Bool]
    public var inLibrary: [String: Bool]
    public var container: Container?
    public var releaseGroup: String?
    public var releaseGroupNormalized: String?
    public var remux: Bool
    public var edition: String?
    public var year: Int?
    public var yearRange: (Int, Int)?
    public var season: Int?
    public var episode: Int?
    public var seasonPack: Bool
    public var discIndex: Int?
    public var repackIteration: Int
    public var proper: Bool
    public var hardcoded: Bool
    public var animeHash: String?
    public var scamScore: Int

    public init(
        stream: EngineStream = EngineStream(),
        parsedTitle: String = "", episodeTitle: String? = nil,
        resolution: Resolution = .sd, hdrFormat: HdrFormat? = nil,
        codec: Codec = .other, source: Source = .other,
        audio: AudioInfo = AudioInfo(), audioLanguages: [String] = [],
        size: UInt64? = nil, seeders: UInt32? = nil,
        cached: [String: Bool] = [:], inLibrary: [String: Bool] = [:],
        container: Container? = nil, releaseGroup: String? = nil,
        releaseGroupNormalized: String? = nil, remux: Bool = false,
        edition: String? = nil, year: Int? = nil, yearRange: (Int, Int)? = nil,
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

// Codable support for the yearRange tuple (Rust encodes as [start, end] array).
extension ParsedStream {
    private enum CodingKeys: String, CodingKey {
        case stream, parsedTitle, episodeTitle, resolution, hdrFormat, codec, source
        case audio, audioLanguages, size, seeders, cached, inLibrary, container
        case releaseGroup, releaseGroupNormalized, remux, edition, year, yearRange
        case season, episode, seasonPack, discIndex, repackIteration, proper
        case hardcoded, animeHash, scamScore
    }

    public init(from decoder: Decoder) throws {
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
            yearRange = (arr[0], arr[1])
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

    public func encode(to encoder: Encoder) throws {
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
        if let yearRange { try c.encode([yearRange.0, yearRange.1], forKey: .yearRange) }
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

public struct ScoreReason: Codable, Equatable, Sendable {
    public var signal: String
    public var delta: Double

    public init(signal: String, delta: Double) {
        self.signal = signal
        self.delta = delta
    }
}

public struct ScoredStream: Codable, Equatable, Sendable {
    public var parsed: ParsedStream
    public var score: Double
    public var reasons: [ScoreReason]
    public var tier: Tier

    public init(parsed: ParsedStream, score: Double, reasons: [ScoreReason], tier: Tier) {
        self.parsed = parsed
        self.score = score
        self.reasons = reasons
        self.tier = tier
    }
}

public struct RankedPicker: Codable, Equatable, Sendable {
    public var primary: ScoredStream?
    public var byTier: [String: ScoredStream]
    public var all: [ScoredStream]

    public init(primary: ScoredStream? = nil, byTier: [String: ScoredStream] = [:], all: [ScoredStream] = []) {
        self.primary = primary
        self.byTier = byTier
        self.all = all
    }
}

public struct TrustOptions: Codable, Equatable, Sendable {
    public var kind: String?
    public var expectedTitle: String?
    public var expectedYear: Int?
    public var expectedSeason: Int?
    public var expectedEpisode: Int?
    public var releaseDate: String?
    public var allowSeasonPacks: Bool
    public var allowCam: Bool
    public var allowSizeOutliers: Bool
    public var strict: Bool
    public var disabled: Bool
    public var preferredLanguages: [String]
    public var preferredAudioLangs: [String]
    public var requirePreferredLanguage: Bool
    public var isAnime: Bool

    public init(
        kind: String? = nil, expectedTitle: String? = nil, expectedYear: Int? = nil,
        expectedSeason: Int? = nil, expectedEpisode: Int? = nil, releaseDate: String? = nil,
        allowSeasonPacks: Bool = false, allowCam: Bool = false, allowSizeOutliers: Bool = false,
        strict: Bool = true, disabled: Bool = false, preferredLanguages: [String] = [],
        preferredAudioLangs: [String] = [], requirePreferredLanguage: Bool = false,
        isAnime: Bool = false
    ) {
        self.kind = kind; self.expectedTitle = expectedTitle; self.expectedYear = expectedYear
        self.expectedSeason = expectedSeason; self.expectedEpisode = expectedEpisode
        self.releaseDate = releaseDate; self.allowSeasonPacks = allowSeasonPacks
        self.allowCam = allowCam; self.allowSizeOutliers = allowSizeOutliers
        self.strict = strict; self.disabled = disabled
        self.preferredLanguages = preferredLanguages
        self.preferredAudioLangs = preferredAudioLangs
        self.requirePreferredLanguage = requirePreferredLanguage
        self.isAnime = isAnime
    }
}

public struct Rejection: Codable, Equatable, Sendable {
    public var stream: ParsedStream
    public var reason: String

    public init(stream: ParsedStream, reason: String) {
        self.stream = stream
        self.reason = reason
    }
}

public struct ScoreOptions: Codable, Equatable, Sendable {
    public var activeDebrids: [String]
    public var preferredLanguages: [String]
    public var releaseDate: String?
    public var mediaKind: String?
    public var runtimeMinutes: Int?
    public var inTheaters: Bool
    public var respectAddonOrder: Bool
    public var preferredReleaseGroup: String?
    public var bandwidthMbps: Double?
    public var preferSingleAudioTrack: Bool
    public var preferAddonId: String?

    public init(
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

public struct CorpusStats: Codable, Equatable, Sendable {
    public var daysSinceRelease: Double?
    public var trustedTrackedFraction: Double
    public var theaterCaptureFraction: Double
    public var webishFraction: Double
    public var trustedTrackedCount: Int

    public init(
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
