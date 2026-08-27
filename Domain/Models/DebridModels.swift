import Foundation

struct RealDebridAddMagnetResponse: Codable, Sendable {
    let id: String
}

struct RealDebridFile: Codable, Sendable {
    let id: Int
    let path: String
    let bytes: Int64
    let selected: Int
    let link: String?
}

struct RealDebridTorrentInfo: Codable, Sendable {
    let id: String
    let filename: String
    let status: String?
    let files: [RealDebridFile]?
    let links: [String]?
}

struct RealDebridUnrestrictResponse: Codable, Sendable {
    let download: String
    let filename: String?
}
