import Foundation

enum AlbumSort: String, CaseIterable, Identifiable {
    case title, artist, year, recent, random
    var id: String { rawValue }
    var label: String {
        switch self {
        case .title: return "Title"
        case .artist: return "Artist"
        case .year: return "Year"
        case .recent: return "Recently added"
        case .random: return "Random"
        }
    }
}

enum TrackSort: String, CaseIterable {
    case title, artist, album, recent, random
}

enum PlaylistScope: String {
    case mine, `public`, all
}

/// Typed wrappers for the endpoints the app uses. See docs/api/mobile-clients.md in the server repo.
extension APIClient {
    private func q(_ name: String, _ value: CustomStringConvertible?) -> URLQueryItem {
        URLQueryItem(name: name, value: value?.description)
    }

    // MARK: Auth

    static func fetchAuthConfig(server: URL, urlSession: URLSession = .shared) async throws -> AuthConfig {
        let client = APIClient(baseURL: server, credentials: CredentialProvider(credential: .anonymous), urlSession: urlSession)
        return try await client.get("/api/v1/auth/config")
    }

    func me() async throws -> Me { try await get("/api/v1/me") }
    func health() async throws -> Health { try await get("/api/v1/health") }

    func apiTokens() async throws -> [ApiToken] {
        let list: ItemList<ApiToken> = try await get("/api/v1/tokens")
        return list.items
    }

    func createAPIToken(name: String, expiresInDays: Int? = nil) async throws -> NewApiToken {
        struct Body: Encodable { let name: String; let expiresInDays: Int? }
        return try await send("POST", "/api/v1/tokens", body: Body(name: name, expiresInDays: expiresInDays))
    }

    func deleteAPIToken(id: Int) async throws {
        try await send("DELETE", "/api/v1/tokens/\(id)")
    }

    // MARK: Library

    func albums(q search: String? = nil, artistId: Int? = nil, sort: AlbumSort = .title, limit: Int = 50, offset: Int = 0) async throws -> Page<Album> {
        try await get("/api/v1/albums", query: [q("q", search), q("artistId", artistId), q("sort", sort.rawValue), q("limit", limit), q("offset", offset)])
    }

    func album(id: Int) async throws -> AlbumDetail { try await get("/api/v1/albums/\(id)") }

    func artists(q search: String? = nil, limit: Int = 100, offset: Int = 0) async throws -> Page<Artist> {
        try await get("/api/v1/artists", query: [q("q", search), q("limit", limit), q("offset", offset)])
    }

    func artist(id: Int) async throws -> ArtistDetail { try await get("/api/v1/artists/\(id)") }

    func tracks(q search: String? = nil, artistId: Int? = nil, genre: String? = nil, sort: TrackSort = .artist, limit: Int = 100, offset: Int = 0) async throws -> Page<Track> {
        try await get("/api/v1/tracks", query: [q("q", search), q("artistId", artistId), q("genre", genre), q("sort", sort.rawValue), q("limit", limit), q("offset", offset)])
    }

    func genres() async throws -> [Genre] {
        let list: ItemList<Genre> = try await get("/api/v1/genres")
        return list.items
    }

    func search(_ text: String, limit: Int = 20) async throws -> SearchResults {
        try await get("/api/v1/search", query: [q("q", text), q("limit", limit)])
    }

    // MARK: Personal

    func favorites(limit: Int = 100, offset: Int = 0) async throws -> Page<Track> {
        try await get("/api/v1/favorites", query: [q("limit", limit), q("offset", offset)])
    }

    func setFavorite(trackId: Int, _ favorite: Bool) async throws {
        try await send(favorite ? "PUT" : "DELETE", "/api/v1/tracks/\(trackId)/favorite")
    }

    func recordPlay(trackId: Int) async throws {
        try await send("POST", "/api/v1/tracks/\(trackId)/played")
    }

    func history(limit: Int = 50, offset: Int = 0) async throws -> Page<HistoryEntry> {
        try await get("/api/v1/history", query: [q("limit", limit), q("offset", offset)])
    }

    // MARK: Playlists

    func playlists(scope: PlaylistScope = .all) async throws -> [Playlist] {
        let list: ItemList<Playlist> = try await get("/api/v1/playlists", query: [q("scope", scope.rawValue)])
        return list.items
    }

    func playlist(id: Int) async throws -> PlaylistDetail { try await get("/api/v1/playlists/\(id)") }

    @discardableResult
    func createPlaylist(name: String, description: String? = nil, isPublic: Bool = false, trackIds: [Int] = []) async throws -> Playlist {
        struct Body: Encodable { let name: String; let description: String?; let isPublic: Bool; let trackIds: [Int] }
        return try await send("POST", "/api/v1/playlists", body: Body(name: name, description: description, isPublic: isPublic, trackIds: trackIds))
    }

    @discardableResult
    func updatePlaylist(id: Int, name: String, description: String?, isPublic: Bool) async throws -> Playlist {
        struct Body: Encodable {
            let name: String; let description: String?; let isPublic: Bool
            // Encode `description: null` explicitly so it can be cleared.
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(name, forKey: .name)
                try c.encode(description, forKey: .description)
                try c.encode(isPublic, forKey: .isPublic)
            }
            enum CodingKeys: String, CodingKey { case name, description, isPublic }
        }
        return try await send("PATCH", "/api/v1/playlists/\(id)", body: Body(name: name, description: description, isPublic: isPublic))
    }

    func deletePlaylist(id: Int) async throws {
        try await send("DELETE", "/api/v1/playlists/\(id)")
    }

    func addToPlaylist(id: Int, trackIds: [Int]) async throws {
        struct Body: Encodable { let trackIds: [Int] }
        try await send("POST", "/api/v1/playlists/\(id)/tracks", body: Body(trackIds: trackIds))
    }

    func removeFromPlaylist(id: Int, entryId: Int) async throws {
        try await send("DELETE", "/api/v1/playlists/\(id)/tracks/\(entryId)")
    }

    func reorderPlaylist(id: Int, entryIds: [Int]) async throws {
        struct Body: Encodable { let entryIds: [Int] }
        try await send("PUT", "/api/v1/playlists/\(id)/order", body: Body(entryIds: entryIds))
    }
}
