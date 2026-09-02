import Foundation

// MARK: - Discover personalization (audit metadata-anime.md §4.1).
// Exact port of Harbor's affinity model: exponential recency half-life 90 days,
// kind weights (open 1.0, play 3.0, dwell 2.5, watchlist 4.0, watched 6.0,
// vote_up 5.0, vote_down −5.0), category weights (cast 1.0, directors 1.5,
// creators 1.5, genres 0.8, keywords 1.2, decade 0.4, language 0.3).

public enum DiscoverEventKind: String, Codable, Sendable {
    case open, dwell, play, watchlist, watched, voteUp, voteDown
}

public struct DiscoverEvent: Codable, Equatable, Sendable {
    public var kind: DiscoverEventKind
    public var metaId: String
    public var metaType: String
    public var timestamp: Date

    public init(kind: DiscoverEventKind, metaId: String, metaType: String, timestamp: Date = Date()) {
        self.kind = kind
        self.metaId = metaId
        self.metaType = metaType
        self.timestamp = timestamp
    }
}

public struct ProfileSnapshot: Codable, Equatable, Sendable {
    public var cast: [Int]      // TMDB person ids (top 5)
    public var directors: [Int]
    public var creators: [Int]
    public var genres: [String]
    public var keywords: [Int]  // TMDB keyword ids
    public var decade: Int?
    public var language: String?

    public init(
        cast: [Int] = [], directors: [Int] = [], creators: [Int] = [],
        genres: [String] = [], keywords: [Int] = [], decade: Int? = nil,
        language: String? = nil
    ) {
        self.cast = cast
        self.directors = directors
        self.creators = creators
        self.genres = genres
        self.keywords = keywords
        self.decade = decade
        self.language = language
    }
}

public struct DiscoverAffinity: Codable, Equatable, Sendable {
    public var cast: [Int: Double]
    public var directors: [Int: Double]
    public var creators: [Int: Double]
    public var genres: [String: Double]
    public var keywords: [Int: Double]
    public var decades: [Int: Double]
    public var languages: [String: Double]

    public init(
        cast: [Int: Double] = [:], directors: [Int: Double] = [:],
        creators: [Int: Double] = [:], genres: [String: Double] = [:],
        keywords: [Int: Double] = [:], decades: [Int: Double] = [:],
        languages: [String: Double] = [:]
    ) {
        self.cast = cast
        self.directors = directors
        self.creators = creators
        self.genres = genres
        self.keywords = keywords
        self.decades = decades
        self.languages = languages
    }

    public var isEmpty: Bool {
        cast.isEmpty && directors.isEmpty && creators.isEmpty && genres.isEmpty
            && keywords.isEmpty && decades.isEmpty && languages.isEmpty
    }
}

public enum DiscoverEngine {

    // Harbor constants (affinity.ts)
    public static let halfLifeDays: Double = 90
    public static let kindWeights: [DiscoverEventKind: Double] = [
        .open: 1.0, .play: 3.0, .dwell: 2.5, .watchlist: 4.0,
        .watched: 6.0, .voteUp: 5.0, .voteDown: -5.0,
    ]
    public static let categoryWeights: [String: Double] = [
        "cast": 1.0, "directors": 1.5, "creators": 1.5, "genres": 0.8,
        "keywords": 1.2, "decade": 0.4, "language": 0.3,
    ]

    /// Harbor's decay: weight halves every 90 days.
    public static func recencyWeight(timestamp: Date, now: Date = Date()) -> Double {
        let ageDays = max(0, now.timeIntervalSince(timestamp) / 86400)
        return pow(0.5, ageDays / halfLifeDays)
    }

    /// Build the affinity model from events + the profile snapshot of each meta.
    /// Events reference metas; profile maps metaId → snapshot (built by the caller
    /// from TMDB detail data — Harbor's personalization depends on TMDB ids).
    public static func buildAffinity(
        events: [DiscoverEvent],
        profiles: [String: ProfileSnapshot],
        now: Date = Date()
    ) -> DiscoverAffinity {
        var affinity = DiscoverAffinity()

        func add(_ dict: inout [Int: Double], key: Int, weight: Double) {
            dict[key, default: 0] += weight
        }
        func addGenre(_ dict: inout [String: Double], key: String, weight: Double) {
            dict[key, default: 0] += weight
        }
        func addDecade(_ dict: inout [Int: Double], key: Int, weight: Double) {
            dict[key, default: 0] += weight
        }
        func addLang(_ dict: inout [String: Double], key: String, weight: Double) {
            dict[key, default: 0] += weight
        }

        for event in events {
            guard let profile = profiles[event.metaId],
                  let kindWeight = kindWeights[event.kind] else { continue }
            let weight = kindWeight * recencyWeight(timestamp: event.timestamp, now: now)
            for id in profile.cast { add(&affinity.cast, key: id, weight: weight * (categoryWeights["cast"] ?? 1)) }
            for id in profile.directors { add(&affinity.directors, key: id, weight: weight * (categoryWeights["directors"] ?? 1)) }
            for id in profile.creators { add(&affinity.creators, key: id, weight: weight * (categoryWeights["creators"] ?? 1)) }
            for genre in profile.genres { addGenre(&affinity.genres, key: genre, weight: weight * (categoryWeights["genres"] ?? 1)) }
            for id in profile.keywords { add(&affinity.keywords, key: id, weight: weight * (categoryWeights["keywords"] ?? 1)) }
            if let decade = profile.decade { addDecade(&affinity.decades, key: decade, weight: weight * (categoryWeights["decade"] ?? 1)) }
            if let language = profile.language { addLang(&affinity.languages, key: language, weight: weight * (categoryWeights["language"] ?? 1)) }
        }
        return affinity
    }

    /// Candidate scoring: weighted average (cast/genres/keywords via mean÷√n) + sums (Harbor's formula).
    public static func score(candidate: ProfileSnapshot, affinity: DiscoverAffinity) -> Double {
        var total = 0.0

        func meanOverSqrt(_ values: [Double]) -> Double {
            guard !values.isEmpty else { return 0 }
            return values.reduce(0, +) / Double(values.count) / sqrt(Double(values.count))
        }

        total += meanOverSqrt(candidate.cast.compactMap { affinity.cast[$0] }) * (categoryWeights["cast"] ?? 1)
        total += meanOverSqrt(candidate.directors.compactMap { affinity.directors[$0] }) * (categoryWeights["directors"] ?? 1)
        total += meanOverSqrt(candidate.creators.compactMap { affinity.creators[$0] }) * (categoryWeights["creators"] ?? 1)
        total += meanOverSqrt(candidate.genres.compactMap { affinity.genres[$0] }) * (categoryWeights["genres"] ?? 1)
        total += meanOverSqrt(candidate.keywords.compactMap { affinity.keywords[$0] }) * (categoryWeights["keywords"] ?? 1)
        if let decade = candidate.decade, let value = affinity.decades[decade] {
            total += value * (categoryWeights["decade"] ?? 1)
        }
        if let language = candidate.language, let value = affinity.languages[language] {
            total += value * (categoryWeights["language"] ?? 1)
        }
        return total
    }
}

// MARK: - Event store (Harbor: 500-event cap, 5s debounced persist, 90s duplicate window)

public actor DiscoverEventStore {

    public static let shared = DiscoverEventStore()

    public static let maxEvents = 500
    public static let duplicateWindow: TimeInterval = 90

    private let cache: AppCache
    private var events: [DiscoverEvent] = []

    public init(cache: AppCache = .shared) {
        self.cache = cache
        self.events = cache.get([DiscoverEvent].self, key: "events", namespace: "discover") ?? []
    }

    public func record(_ event: DiscoverEvent) async {
        // 90s duplicate window (same kind + meta).
        let now = Date()
        if events.contains(where: {
            $0.kind == event.kind && $0.metaId == event.metaId
                && now.timeIntervalSince($0.timestamp) < Self.duplicateWindow
        }) {
            return
        }
        events.append(event)
        if events.count > Self.maxEvents {
            events.removeFirst(events.count - Self.maxEvents)
        }
        cache.set(events, key: "events", namespace: "discover", ttl: nil)
    }

    public func all() async -> [DiscoverEvent] {
        events
    }
}
