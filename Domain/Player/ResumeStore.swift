import Foundation

// MARK: - Resume / progress store (Phase 10, audit player.md §1.5).
// Tick 4s while playing, force-save on pause/end, min 5s position, 150s stub cap,
// dedupe 1.5s delta, watched threshold 0.85 (ended always counts as watched).

struct PlaybackProgress: Codable, Equatable, Sendable {
    var metaId: String
    var streamKey: String
    var url: String?
    var title: String?
    var poster: String?
    var metaType: String
    var positionSeconds: Double
    var durationSeconds: Double
    var watched: Bool
    var updatedAt: Date

    init(
        metaId: String, streamKey: String, url: String? = nil, title: String? = nil,
        poster: String? = nil, metaType: String = "movie",
        positionSeconds: Double = 0, durationSeconds: Double = 0,
        watched: Bool = false, updatedAt: Date = Date()
    ) {
        self.metaId = metaId
        self.streamKey = streamKey
        self.url = url
        self.title = title
        self.poster = poster
        self.metaType = metaType
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.watched = watched
        self.updatedAt = updatedAt
    }

    var resumePosition: Double? {
        guard !watched, durationSeconds > PlaybackPolicy.stubMaxSeconds,
              positionSeconds >= PlaybackPolicy.minimumResumePosition else { return nil }
        return positionSeconds
    }
}

protocol ResumeStoring: Sendable {
    func progress(metaId: String) async -> PlaybackProgress?
    func save(_ progress: PlaybackProgress) async
    func clear(metaId: String) async
}

actor ResumeStore: ResumeStoring {

    static let shared = ResumeStore()

    private let cache: AppCache
    private var lastSaved: [String: (position: Double, at: Date)] = [:]

    init(cache: AppCache = .shared) {
        self.cache = cache
    }

    private func namespace(metaId: String) -> String { "resume/\(metaId.hashValue)" }
    private func key(metaId: String) -> String { "progress-\(metaId)" }
    private var indexKey: String { "resume-index" }

    /// Ordered list of unfinished progress entries (most recent first).
    func allProgress() async -> [PlaybackProgress] {
        let index: [String] = cache.get([String].self, key: indexKey, namespace: "resume-index") ?? []
        var out: [PlaybackProgress] = []
        for metaId in index {
            if let progress = cache.get(PlaybackProgress.self, key: key(metaId: metaId), namespace: namespace(metaId: metaId)),
               progress.resumePosition != nil {
                out.append(progress)
            }
        }
        return out.sorted { $0.updatedAt > $1.updatedAt }
    }

    func progress(metaId: String) async -> PlaybackProgress? {
        cache.get(PlaybackProgress.self, key: key(metaId: metaId), namespace: namespace(metaId: metaId))
    }

    /// Harbor's autosave semantics: dedupe 1.5s delta, skip stubs below 150s, min 5s.
    func save(_ progress: PlaybackProgress) async {
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
        // Minimum position 5s (Harbor parity): below-threshold positions are never saved.
        if !p.watched, p.positionSeconds < PlaybackPolicy.minimumResumePosition {
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
        // Maintain the resume index (ordered insertion; allProgress sorts by updatedAt).
        var index: [String] = cache.get([String].self, key: indexKey, namespace: "resume-index") ?? []
        index.removeAll { $0 == p.metaId }
        if p.resumePosition != nil {
            index.insert(p.metaId, at: 0)
        }
        cache.set(index, key: indexKey, namespace: "resume-index", ttl: nil)
    }

    func clear(metaId: String) async {
        cache.remove(key: key(metaId: metaId), namespace: namespace(metaId: metaId))
        var index: [String] = cache.get([String].self, key: indexKey, namespace: "resume-index") ?? []
        index.removeAll { $0 == metaId }
        cache.set(index, key: indexKey, namespace: "resume-index", ttl: nil)
        lastSaved.removeValue(forKey: metaId)
    }
}
