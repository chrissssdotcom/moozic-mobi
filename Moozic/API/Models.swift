import Foundation

// Models mirror docs/api/reference/schemas.md in the server repo. Unknown fields are ignored,
// so new server fields never break decoding. Times are Unix epoch milliseconds.

struct ArtistRef: Codable, Hashable {
    let id: Int
    let name: String
}

struct AlbumRef: Codable, Hashable {
    let id: Int
    let title: String
    let artist: String
    let artistId: Int
}

struct Track: Codable, Hashable, Identifiable {
    let id: Int
    let title: String
    let artist: ArtistRef
    let album: AlbumRef
    let trackNo: Int?
    let trackTotal: Int?
    let discNo: Int?
    let discTotal: Int?
    let year: Int?
    let genre: String?
    let duration: Double?
    let bitrate: Int?
    let sampleRate: Int?
    let codec: String?
    let size: Int
    let hasCover: Bool
    let favorite: Bool
    let streamUrl: String
    let coverUrl: String
}

/// A track inside a playlist; `entryId` identifies this occurrence (a track can appear twice).
struct PlaylistEntry: Decodable, Hashable, Identifiable {
    let entryId: Int
    let position: Int
    let track: Track
    var id: Int { entryId }

    private enum CodingKeys: String, CodingKey { case entryId, position }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entryId = try container.decode(Int.self, forKey: .entryId)
        position = try container.decode(Int.self, forKey: .position)
        track = try Track(from: decoder)
    }
}

/// A play from `GET /history`.
struct HistoryEntry: Decodable, Hashable, Identifiable {
    let playedAt: Int64
    let track: Track
    var id: String { "\(track.id)-\(playedAt)" }

    private enum CodingKeys: String, CodingKey { case playedAt }

    init(from decoder: Decoder) throws {
        playedAt = try decoder.container(keyedBy: CodingKeys.self).decode(Int64.self, forKey: .playedAt)
        track = try Track(from: decoder)
    }
}

struct Album: Codable, Hashable, Identifiable {
    let id: Int
    let title: String
    let artist: ArtistRef
    let year: Int?
    let trackCount: Int
    let duration: Double
    let coverUrl: String
}

struct AlbumDetail: Decodable, Identifiable {
    let id: Int
    let title: String
    let artist: ArtistRef
    let year: Int?
    let trackCount: Int
    let duration: Double
    let coverUrl: String
    let tracks: [Track]
}

struct Artist: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let albumCount: Int
    let trackCount: Int
}

struct ArtistDetail: Decodable, Identifiable {
    let id: Int
    let name: String
    let albumCount: Int
    let trackCount: Int
    let albums: [Album]
}

struct Genre: Decodable, Hashable, Identifiable {
    let name: String
    let trackCount: Int
    var id: String { name }
}

struct Page<Item: Decodable>: Decodable {
    let items: [Item]
    let total: Int
    let limit: Int
    let offset: Int

    var hasMore: Bool { offset + items.count < total }
}

struct ItemList<Item: Decodable>: Decodable {
    let items: [Item]
}

struct SearchResults: Decodable {
    let tracks: [Track]
    let albums: [Album]
    let artists: [Artist]

    var isEmpty: Bool { tracks.isEmpty && albums.isEmpty && artists.isEmpty }
}

struct Playlist: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let description: String?
    let isPublic: Bool
    let owner: String?
    let isOwner: Bool
    let trackCount: Int
    let duration: Double
    let createdAt: Int64
    let updatedAt: Int64
}

struct PlaylistDetail: Decodable, Identifiable {
    let id: Int
    let name: String
    let description: String?
    let isPublic: Bool
    let owner: String?
    let isOwner: Bool
    let trackCount: Int
    let duration: Double
    let tracks: [PlaylistEntry]
}

struct Me: Decodable, Equatable {
    let id: Int
    let username: String?
    let email: String?
    let name: String?
    let isAdmin: Bool
    let authMethod: String?

    var displayName: String { name ?? username ?? email ?? "User \(id)" }
}

struct ApiToken: Decodable, Identifiable {
    let id: Int
    let name: String
    let prefix: String
    let createdAt: Int64
    let lastUsedAt: Int64?
    let expiresAt: Int64?
}

struct NewApiToken: Decodable {
    let id: Int
    let name: String
    let token: String
    let expiresAt: Int64?
}

struct Health: Decodable {
    let status: String
    let version: String
}

extension Int64 {
    /// Unix epoch milliseconds → Date.
    var epochMillisDate: Date { Date(timeIntervalSince1970: TimeInterval(self) / 1000) }
}
