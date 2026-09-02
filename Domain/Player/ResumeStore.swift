import Foundation

// MARK: - Resume / progress store (Phase 10, audit player.md §1.5).
// Tick 4s while playing, force-save on pause/end, min 5s position, 150s stub cap,
// dedupe 1.5s delta, watched threshold 0.85 (ended always counts as watched).

public struct PlaybackProgress: Codable, Equatable, Sendable {
    public var metaId: String
    public var streamKey: String
    public var url: String?
    public var title: String?
    public var positionSeconds: Double
    public var durationSeconds: Double
    public var watched: Bool
    public var updatedAt: Date

    public init(
        metaId: String, streamKey: String, url: String? = nil, title: String? = nil,
        positionSeconds: Double = 0, durationSeconds: Double = 0,
        watched: Bool = false, updatedAt: Date = Date()
    ) {
        self.metaId = metaId
        self.streamKey = streamKey
        self.url = url
        self.title = title
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.watched = watched
        self.updatedAt = updatedAt
    }

    public var resumePosition: Double? {
        guard !watched, durationSeconds > PlaybackPolicy.stubMaxSeconds,
              positionSeconds >= PlaybackPolicy.minimumResumePosition else { return nil }
        return positionSeconds
    }
}

public protocol ResumeStoring: Sendable {
    func progress(metaId: String) async -> PlaybackProgress?
    func save(_ progress: PlaybackProgress) async
    func clear(metaId: String) async
}

public actor ResumeStore: ResumeStoring {

    public static let shared = ResumeStore()

    private let cache: AppCache
    private var lastSaved: [String: (position: Double, at: Date)] = [:]

    public init(cache: AppCache = .shared) {
        self.cache = cache
    }

    private func namespace(metaId: String) -> String { "resume/\(metaId.hashValue)" }
    private func key(metaId: String) -> String { "progress-\(metaId)" }

    public func progress(metaId: String) async -> PlaybackProgress? {
        cache.get(PlaybackProgress.self, key: key(metaId: metaId), namespace: namespace(metaId: metaId))
    }

    /// Harbor's autosave semantics: dedupe 1.5s delta, skip stubs below 150s, min 5s.
    public func save(_ progress: PlaybackProgress) async {
        var p = progress
        // Ended → watched. Past 85% → watched (Harbor's threshold).
        let isEnded = p.durationSeconds > 0 && p.positionSeconds >= p.durationSeconds - 1
        if isEnded || (p.durationSeconds > 0 && p.positionSeconds / p.durationSeconds >= PlaybackPolicy.watchedRatio) {
            p.watched = true
        }
        // No saves for stubs.
        if p.durationSeconds > 0, p.durationSeconds < PlaybackPolicy.stubMaxSeconds, !p.watched {
            return
        }
        // Dedupe: 1.5s delta on non-terminal saves.
        if !p.watched, p.positionSeconds >= PlaybackPolicy.minimumResumePosition {
            let now = Date()
            if let last = lastSaved[p.metaId],
               now.timeIntervalSince(last.at) < PlaybackPolicy.resumeDedupeDelta,
               abs(last.position - p.positionSeconds) < PlaybackPolicy.resumeDedupeDelta {
                return
            }
            lastSaved[p.metaId] = (p.positionSeconds, now)
        }
        cache.set(p, key: key(metaId: p.metaId), namespace: namespace(metaId: p.metaId), ttl: nil)
    }

    public func clear(metaId: String) async {
        cache.remove(key: key(metaId: metaId), namespace: namespace(metaId: metaId))
        lastSaved.removeValue(forKey: metaId)
    }
}
