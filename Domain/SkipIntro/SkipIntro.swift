import Foundation

// MARK: - Skip intro/outro/recap (Phase 11 core, audit player.md §6).
// Providers: AniSkip v2, TheIntroDB v2, chapter classification, Harbor ad-corpus.
// Merge: priority [ad, aniSkip, introDb, chapters], first-wins on overlap, 2–360s
// segments, outros only after 50% of duration, active window uses 0.75s tail margin.
// MANUAL pill only — Harbor has no auto-skip (FACT).

public enum SkipKind: String, Codable, Sendable, Equatable {
    case intro, outro, recap, ad
}

public enum SkipSource: String, Codable, Sendable, Equatable {
    case aniskip, introdb, chapters, adcorpus
}

public struct SkipSegment: Codable, Equatable, Sendable, Identifiable {
    public var startSeconds: Double
    public var endSeconds: Double
    public var kind: SkipKind
    public var source: SkipSource

    public var id: String { "\(source.rawValue)-\(kind.rawValue)-\(Int(startSeconds))" }

    public init(startSeconds: Double, endSeconds: Double, kind: SkipKind, source: SkipSource) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.kind = kind
        self.source = source
    }
}

public struct ChapterInfo: Codable, Equatable, Sendable {
    public var title: String
    public var startSeconds: Double
    public var endSeconds: Double?

    public init(title: String, startSeconds: Double, endSeconds: Double? = nil) {
        self.title = title
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }
}

// MARK: - Providers

public protocol SkipIntroProviding: Sendable {
    func segments(media: SkipIntroMedia) async -> [SkipSegment]
}

public struct SkipIntroMedia: Sendable {
    public var imdbId: String?
    public var tmdbId: Int?
    public var malId: Int?
    public var kitsuId: String?
    public var season: Int?
    public var episode: Int?
    public var durationSeconds: Double

    public init(
        imdbId: String? = nil, tmdbId: Int? = nil, malId: Int? = nil, kitsuId: String? = nil,
        season: Int? = nil, episode: Int? = nil, durationSeconds: Double
    ) {
        self.imdbId = imdbId
        self.tmdbId = tmdbId
        self.malId = malId
        self.kitsuId = kitsuId
        self.season = season
        self.episode = episode
        self.durationSeconds = durationSeconds
    }
}

/// AniSkip v2 (audit §6.1): GET https://api.aniskip.com/v2/skip-times/{malId}/{episode}?types=op&types=ed&types=mixed-op&types=mixed-ed&types=recap&episodeLength={sec}
public actor AniSkipProvider: SkipIntroProviding {

    public static let shared = AniSkipProvider()
    private let network: NetworkClient

    public init(network: NetworkClient = .shared) {
        self.network = network
    }

    private struct AniSkipResponse: Decodable {
        struct Result: Decodable {
            struct Interval: Decodable { var startTime: Double; var endTime: Double }
            var interval: Interval
            var skipType: String
        }
        var found: Bool
        var results: [Result]?
    }

    public func segments(media: SkipIntroMedia) async -> [SkipSegment] {
        guard let malId = media.malId, let episode = media.episode else { return [] }
        var components = URLComponents(string: "https://api.aniskip.com/v2/skip-times/\(malId)/\(episode)")!
        components.queryItems = [
            URLQueryItem(name: "types", value: "op"),
            URLQueryItem(name: "types", value: "ed"),
            URLQueryItem(name: "types", value: "mixed-op"),
            URLQueryItem(name: "types", value: "mixed-ed"),
            URLQueryItem(name: "types", value: "recap"),
            URLQueryItem(name: "episodeLength", value: String(Int(media.durationSeconds))),
        ]
        guard let url = components.url else { return [] }
        do {
            let response: AniSkipResponse = try await network.get(AniSkipResponse.self, url: url, policy: .none)
            guard response.found, let results = response.results else { return [] }
            return results.map { result in
                let kind: SkipKind = {
                    switch result.skipType {
                    case "ed", "mixed-ed": return .outro
                    case "recap": return .recap
                    default: return .intro
                    }
                }()
                return SkipSegment(
                    startSeconds: result.interval.startTime,
                    endSeconds: result.interval.endTime,
                    kind: kind, source: .aniskip
                )
            }
        } catch {
            return []
        }
    }
}

/// TheIntroDB v2 (audit §6.2): GET https://api.theintrodb.org/v2/media?tmdb_id=... or ?imdb_id=tt...
/// spans in ms: intro, recap, credits, preview (credits+preview → outro; missing end → duration).
public actor TheIntroDBProvider: SkipIntroProviding {

    public static let shared = TheIntroDBProvider()
    private let network: NetworkClient

    public init(network: NetworkClient = .shared) {
        self.network = network
    }

    private struct IntroDBResponse: Decodable {
        struct Span: Decodable {
            var type: String?
            var start_ms: Int64?
            var end_ms: Int64?
        }
        var spans: [Span]?
    }

    public func segments(media: SkipIntroMedia) async -> [SkipSegment] {
        var components = URLComponents(string: "https://api.theintrodb.org/v2/media")!
        var items: [URLQueryItem] = []
        if let tmdbId = media.tmdbId {
            items.append(URLQueryItem(name: "tmdb_id", value: String(tmdbId)))
        } else if let imdbId = media.imdbId {
            items.append(URLQueryItem(name: "imdb_id", value: imdbId))
        } else {
            return []
        }
        if let season = media.season { items.append(URLQueryItem(name: "season", value: String(season))) }
        if let episode = media.episode { items.append(URLQueryItem(name: "episode", value: String(episode))) }
        components.queryItems = items
        guard let url = components.url else { return [] }
        do {
            let response: IntroDBResponse = try await network.get(IntroDBResponse.self, url: url, policy: .none)
            return (response.spans ?? []).compactMap { span in
                guard let startMs = span.start_ms else { return nil }
                let start = Double(startMs) / 1000
                let end = span.end_ms.map { Double($0) / 1000 } ?? media.durationSeconds
                let type = span.type?.lowercased() ?? ""
                let kind: SkipKind = type.contains("recap") ? .recap : (type.contains("credits") || type.contains("preview") ? .outro : .intro)
                return SkipSegment(startSeconds: start, endSeconds: end, kind: kind, source: .introdb)
            }
        } catch {
            return []
        }
    }
}

// MARK: - Chapter classification (audit §6.3, port of chapters.ts)

public enum ChapterSkipClassifier {

    static let recapRegex = try! NSRegularExpression(pattern: "recap|previously", options: [.caseInsensitive])
    static let introRegex = try! NSRegularExpression(
        pattern: "opening|op\\b|intro|opening credits|theme song", options: [.caseInsensitive])
    static let outroRegex = try! NSRegularExpression(
        pattern: "ending|ed\\b|outro|end credits|closing credits|credits", options: [.caseInsensitive])

    public static func segments(from chapters: [ChapterInfo], durationSeconds: Double) -> [SkipSegment] {
        var out: [SkipSegment] = []
        for (index, chapter) in chapters.enumerated() {
            let end = chapter.endSeconds ?? (index + 1 < chapters.count ? chapters[index + 1].startSeconds : durationSeconds)
            let endClamped = end > chapter.startSeconds ? end : min(durationSeconds, chapter.startSeconds + 90)
            let title = chapter.title.lowercased()
            let range = NSRange(title.startIndex..., in: title)
            if recapRegex.firstMatch(in: title, range: range) != nil {
                out.append(SkipSegment(startSeconds: chapter.startSeconds, endSeconds: endClamped, kind: .recap, source: .chapters))
            } else if introRegex.firstMatch(in: title, range: range) != nil {
                out.append(SkipSegment(startSeconds: chapter.startSeconds, endSeconds: endClamped, kind: .intro, source: .chapters))
            } else if outroRegex.firstMatch(in: title, range: range) != nil {
                out.append(SkipSegment(startSeconds: chapter.startSeconds, endSeconds: endClamped, kind: .outro, source: .chapters))
            }
        }
        return out
    }
}

// MARK: - Merge (audit §6.5: priority ad > aniSkip > introDb > chapters, first-wins on overlap)

public enum SkipSegmentMerger {

    public static func merge(
        aniSkip: [SkipSegment],
        introDB: [SkipSegment],
        chapters: [SkipSegment],
        adCorpus: [SkipSegment] = [],
        durationSeconds: Double
    ) -> [SkipSegment] {
        let ordered = adCorpus + aniSkip + introDB + chapters
        var accepted: [SkipSegment] = []
        for candidate in ordered.sorted(by: { $0.startSeconds < $1.startSeconds }) {
            let length = candidate.endSeconds - candidate.startSeconds
            guard length >= PlaybackPolicy.skipSegmentMinSeconds,
                  length <= PlaybackPolicy.skipSegmentMaxSeconds,
                  candidate.endSeconds <= durationSeconds else { continue }
            // Outros only after 50% of duration.
            if candidate.kind == .outro, candidate.startSeconds < durationSeconds * PlaybackPolicy.skipOutroMinStartFraction {
                continue
            }
            // First-wins on overlap.
            let overlaps = accepted.contains { $0.startSeconds < candidate.endSeconds && $0.endSeconds > candidate.startSeconds }
            if !overlaps {
                accepted.append(candidate)
            }
        }
        return accepted.sorted(by: { $0.startSeconds < $1.startSeconds })
    }

    /// Harbor's activeSegment: position ≥ start && position < end − 0.75s.
    public static func activeSegment(at position: Double, in segments: [SkipSegment]) -> SkipSegment? {
        segments.first {
            position >= $0.startSeconds && position < $0.endSeconds - PlaybackPolicy.skipSegmentActiveTailMargin
        }
    }
}
