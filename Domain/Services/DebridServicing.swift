import Foundation

protocol DebridServicing: Sendable {
    func resolve(
        infoHash: String,
        fileIdx: Int?,
        streamName: String?,
        apiKey: String
    ) async throws -> URL
}

enum DebridResolver {
    static func magnetURI(infoHash: String, name: String?) -> String? {
        let hash = infoHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard hash.count == 40, hash.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }

        var components = ["magnet:?xt=urn:btih:\(hash)"]
        if let name, !name.isEmpty {
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: "&=")
            let encoded = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
            components.append("dn=\(encoded)")
        }
        components.append("tr=udp%3A%2F%2Ftracker.openbittorrent.com%3A80")
        components.append("tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce")
        return components.joined(separator: "&")
    }

    static func fileIndex(in files: [RealDebridFile], preferred: Int?) -> Int? {
        guard !files.isEmpty else { return nil }
        if let preferred, files.indices.contains(preferred) {
            return preferred
        }
        if let largestVideo = files.enumerated()
            .filter({ isVideoPath($0.element.path) })
            .max(by: { $0.element.bytes < $1.element.bytes }) {
            return largestVideo.offset
        }
        return files.enumerated().max(by: { $0.element.bytes < $1.element.bytes })?.offset
    }

    static func isVideoPath(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["mkv", "mp4", "avi", "m4v", "mov", "webm", "ts", "wmv", "flv", "mpg", "mpeg"]
            .contains(ext)
    }
}

enum DebridResolveError: Error, Equatable, LocalizedError {
    case missingAPIKey
    case invalidInfoHash
    case torrentNotReady
    case noPlayableFile
    case api(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add your Real-Debrid API key in Settings to play torrent sources."
        case .invalidInfoHash:
            "The addon returned an invalid torrent hash."
        case .torrentNotReady:
            "Real-Debrid is still preparing this torrent. Try again in a moment."
        case .noPlayableFile:
            "Real-Debrid returned no playable video file for this torrent."
        case .api(let message):
            "Real-Debrid error: \(message)"
        }
    }
}
