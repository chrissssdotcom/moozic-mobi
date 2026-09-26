import XCTest
@testable import Moozic

final class ModelTests: XCTestCase {
    static let trackJSON = """
    {
      "id": 42, "title": "Song", "artist": {"id": 3, "name": "Artist"},
      "album": {"id": 7, "title": "Album", "artist": "Album Artist", "artistId": 4},
      "trackNo": 2, "trackTotal": 10, "discNo": null, "discTotal": null, "year": 1999, "genre": "Rock",
      "duration": 215.4, "bitrate": 320000, "sampleRate": 44100, "codec": "MPEG 1 Layer 3", "size": 8612345,
      "hasCover": true, "favorite": false, "issues": ["missing_year"],
      "musicbrainz": {"recordingId": null, "releaseId": null}, "path": "A/B/02 Song.mp3", "addedAt": 1700000000000,
      "streamUrl": "/api/v1/tracks/42/stream", "coverUrl": "/api/v1/albums/7/cover", "someFutureField": {"x": 1}
    }
    """

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testTrackDecodesAndIgnoresUnknownFields() throws {
        let track = try decode(Track.self, Self.trackJSON)
        XCTAssertEqual(track.id, 42)
        XCTAssertEqual(track.album.artistId, 4)
        XCTAssertNil(track.discNo)
        XCTAssertEqual(track.duration, 215.4)
        XCTAssertEqual(track.streamUrl, "/api/v1/tracks/42/stream")
    }

    func testPlaylistEntryAndHistoryEntryFlattenTrackFields() throws {
        let entryJSON = Self.trackJSON.replacingOccurrences(of: "\"id\": 42,", with: "\"id\": 42, \"entryId\": 900, \"position\": 3,")
        let entry = try decode(PlaylistEntry.self, entryJSON)
        XCTAssertEqual(entry.entryId, 900)
        XCTAssertEqual(entry.position, 3)
        XCTAssertEqual(entry.track.title, "Song")

        let historyJSON = Self.trackJSON.replacingOccurrences(of: "\"id\": 42,", with: "\"id\": 42, \"playedAt\": 1700000001000,")
        let played = try decode(HistoryEntry.self, historyJSON)
        XCTAssertEqual(played.playedAt.epochMillisDate, Date(timeIntervalSince1970: 1_700_000_001))
        XCTAssertEqual(played.track.id, 42)
    }

    func testPage() throws {
        let page = try decode(Page<Artist>.self, """
        {"items": [{"id": 1, "name": "A", "albumCount": 2, "trackCount": 20}], "total": 51, "limit": 1, "offset": 50}
        """)
        XCTAssertEqual(page.items.first?.name, "A")
        XCTAssertFalse(page.hasMore)
    }

    func testAuthConfigForDisabledServer() throws {
        let config = try decode(AuthConfig.self, #"{"mode": "disabled"}"#)
        XCTAssertTrue(config.isAuthDisabled)
        XCTAssertFalse(config.supportsOIDC)
    }

    func testFormatting() {
        XCTAssertEqual(Format.duration(215.9), "3:35")
        XCTAssertEqual(Format.duration(3725), "1:02:05")
        XCTAssertEqual(Format.duration(nil), "–:––")
        XCTAssertEqual(Format.longDuration(2520), "42 min")
        XCTAssertEqual(Format.longDuration(4320), "1 hr 12 min")
        XCTAssertEqual(Format.count(1, "song"), "1 song")
        XCTAssertEqual(Format.count(3, "song"), "3 songs")
    }
}
