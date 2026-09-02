import Foundation

// MARK: - Bounded, TTL-aware, memory-pressure-aware cache (Phase 3, spec §78).
// Disk-backed (Caches/<namespace>/<key>.json) with an in-memory LRU hot layer.
// All caches must be bounded, invalidatable, versioned, concurrency-safe.

public struct CacheEntry: Codable {
    public var storedAt: Date
    public var expiresAt: Date?
    public var payload: Data
}

public final class AppCache: @unchecked Sendable {

    public static let shared = AppCache()

    private let fileManager: FileManager
    private let cacheDirectory: URL
    private let lock = NSLock()
    private var memoryEntries: [String: (entry: CacheEntry, lastAccess: Date)] = [:]

    private let memoryEntryCap = 256
    private let memoryByteCap = 64 * 1024 * 1024   // 64 MiB hot layer

    private var memoryObserver: NSObjectProtocol?

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = base.appendingPathComponent("HarborCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.lock.lock()
            self?.memoryEntries.removeAll(keepingCapacity: false)
            self?.lock.unlock()
        }
    }

    deinit {
        if let memoryObserver {
            NotificationCenter.default.removeObserver(memoryObserver)
        }
    }

    private func diskURL(key: String, namespace: String) -> URL {
        cacheDirectory
            .appendingPathComponent(namespace, isDirectory: true)
            .appendingPathComponent(key)
            .appendingPathExtension("json")
    }

    private func isExpired(_ entry: CacheEntry, now: Date = Date()) -> Bool {
        guard let expiresAt = entry.expiresAt else { return false }
        return now > expiresAt
    }

    /// Reads from memory, then disk, then nil. Expired entries are dropped.
    public func get<T: Decodable>(_ type: T.Type, key: String, namespace: String) -> T? {
        let fullKey = "\(namespace)/\(key)"
        let now = Date()

        lock.lock()
        if let hit = memoryEntries[fullKey], !isExpired(hit.entry, now: now) {
            memoryEntries[fullKey]?.lastAccess = now
            lock.unlock()
            return try? JSONDecoder().decode(T.self, from: hit.entry.payload)
        }
        lock.unlock()

        let url = diskURL(key: key, namespace: namespace)
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(CacheEntry.self, from: data),
              !isExpired(entry, now: now) else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        lock.lock()
        memoryEntries[fullKey] = (entry, now)
        trimMemoryLocked()
        lock.unlock()
        return try? JSONDecoder().decode(T.self, from: entry.payload)
    }

    public func set<T: Encodable>(_ value: T, key: String, namespace: String, ttl: TimeInterval? = nil) {
        guard let payload = try? JSONEncoder().encode(value) else { return }
        let now = Date()
        let entry = CacheEntry(
            storedAt: now,
            expiresAt: ttl.map { now.addingTimeInterval($0) },
            payload: payload
        )
        let url = diskURL(key: key, namespace: namespace)
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try payloadWrapper(entry).write(to: url, options: .atomic)
        } catch {
            return
        }
        lock.lock()
        memoryEntries["\(namespace)/\(key)"] = (entry, now)
        trimMemoryLocked()
        lock.unlock()
    }

    public func remove(key: String, namespace: String) {
        let url = diskURL(key: key, namespace: namespace)
        try? fileManager.removeItem(at: url)
        lock.lock()
        memoryEntries.removeValue(forKey: "\(namespace)/\(key)")
        lock.unlock()
    }

    public func removeAll(namespace: String) {
        let dir = cacheDirectory.appendingPathComponent(namespace, isDirectory: true)
        try? fileManager.removeItem(at: dir)
        lock.lock()
        memoryEntries = memoryEntries.filter { !$0.key.hasPrefix("\(namespace)/") }
        lock.unlock()
    }

    public func pruneExpired() {
        lock.lock()
        let now = Date()
        for (key, item) in memoryEntries where isExpired(item.entry, now: now) {
            memoryEntries.removeValue(forKey: key)
        }
        lock.unlock()
        let contents = (try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for dir in contents where dir.hasDirectoryPath {
            let files = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files {
                guard let data = try? Data(contentsOf: file),
                      let entry = try? JSONDecoder().decode(CacheEntry.self, from: data),
                      isExpired(entry, now: now) else { continue }
                try? fileManager.removeItem(at: file)
            }
        }
    }

    private func payloadWrapper(_ entry: CacheEntry) throws -> Data {
        try JSONEncoder().encode(entry)
    }

    private func trimMemoryLocked() {
        // Evict by count.
        while memoryEntries.count > memoryEntryCap {
            if let oldest = memoryEntries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
                memoryEntries.removeValue(forKey: oldest)
            } else { break }
        }
        // Evict by bytes.
        var total = memoryEntries.values.reduce(0) { $0 + $1.entry.payload.count }
        while total > memoryByteCap {
            guard let oldest = memoryEntries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key else { break }
            total -= memoryEntries[oldest]?.entry.payload.count ?? 0
            memoryEntries.removeValue(forKey: oldest)
        }
    }
}
