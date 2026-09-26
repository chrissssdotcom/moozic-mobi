import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var session: SessionStore

    private struct HomeData {
        var recent: [Album]
        var jumpBackIn: [Album]
        var discover: [Album]
    }

    var body: some View {
        LoadingView(load: Self.load) { data in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if data.recent.isEmpty && data.discover.isEmpty {
                        ContentUnavailableView("Your library is empty", systemImage: "music.note.house", description: Text("Add music to the server's music folder and run a library scan."))
                            .padding(.top, 60)
                    }
                    if !data.jumpBackIn.isEmpty {
                        AlbumShelf(title: "Jump back in", albums: data.jumpBackIn, destination: .history)
                    }
                    if !data.recent.isEmpty {
                        AlbumShelf(title: "Recently added", albums: data.recent, destination: .albums)
                    }
                    if !data.discover.isEmpty {
                        AlbumShelf(title: "Discover", albums: data.discover, destination: nil)
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle(greeting)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        if let first = session.me?.name?.split(separator: " ").first { return "\(part), \(first)" }
        return part
    }

    private static func load(_ api: APIClient) async throws -> HomeData {
        async let recent = api.albums(sort: .recent, limit: 20)
        async let random = api.albums(sort: .random, limit: 20)
        async let history = api.history(limit: 100)
        // Distinct albums from recent plays, most recent first.
        var seen = Set<Int>()
        var jumpBackIn: [Album] = []
        for entry in try await history.items where seen.insert(entry.track.album.id).inserted {
            let t = entry.track
            jumpBackIn.append(Album(
                id: t.album.id,
                title: t.album.title,
                artist: ArtistRef(id: t.album.artistId, name: t.album.artist),
                year: t.year, trackCount: 0, duration: 0, coverUrl: t.coverUrl
            ))
            if jumpBackIn.count == 12 { break }
        }
        return HomeData(recent: try await recent.items, jumpBackIn: jumpBackIn, discover: try await random.items)
    }
}

/// Horizontal row of album covers with a heading.
struct AlbumShelf: View {
    let title: String
    let albums: [Album]
    let destination: Route?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.title2.weight(.bold))
                Spacer()
                if let destination {
                    NavigationLink("See All", value: destination).font(.subheadline)
                }
            }
            .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(albums) { album in
                        NavigationLink(value: Route.album(album.id)) {
                            AlbumTile(album: album).frame(width: 150)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct AlbumTile: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CoverArt(path: album.coverUrl)
            Text(album.title).font(.subheadline.weight(.medium)).lineLimit(1)
            Text(album.artist.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}
