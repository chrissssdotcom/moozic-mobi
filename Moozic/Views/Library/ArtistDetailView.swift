import SwiftUI

struct ArtistDetailView: View {
    let artistId: Int

    var body: some View {
        LoadingView(load: { try await $0.artist(id: artistId) }) { artist in
            ArtistContent(artist: artist)
        }
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct ArtistContent: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var player: PlayerController
    let artist: ArtistDetail
    @State private var loadingAll = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(Format.count(artist.albumCount, "album")) · \(Format.count(artist.trackCount, "song"))")
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button { Task { await playAll(shuffle: false) } } label: {
                        Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    Button { Task { await playAll(shuffle: true) } } label: {
                        Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(loadingAll || artist.trackCount == 0)

                Text("Albums").font(.title2.weight(.bold)).padding(.top, 8)
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(artist.albums) { album in
                        NavigationLink(value: Route.album(album.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                CoverArt(path: album.coverUrl)
                                Text(album.title).font(.subheadline.weight(.medium)).lineLimit(1)
                                Text(album.year.map { String($0) } ?? " ").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(artist.name)
    }

    /// Every track by the artist (up to the API's page cap), album by album.
    private func playAll(shuffle: Bool) async {
        guard let api = session.api else { return }
        loadingAll = true
        defer { loadingAll = false }
        guard let page = try? await api.tracks(artistId: artist.id, sort: .album, limit: 500) else { return }
        player.play(page.items, shuffle: shuffle)
    }
}
