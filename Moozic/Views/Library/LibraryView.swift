import SwiftUI

struct LibraryView: View {
    var body: some View {
        List {
            Section {
                link("Albums", "square.stack", .albums)
                link("Artists", "music.mic", .artists)
                link("Songs", "music.note", .songs(genre: nil))
                link("Genres", "guitars", .genres)
                link("Favorites", "heart", .favorites)
                link("Recently Played", "clock.arrow.circlepath", .history)
            }
        }
        .navigationTitle("Library")
    }

    private func link(_ title: String, _ symbol: String, _ route: Route) -> some View {
        NavigationLink(value: route) {
            Label(title, systemImage: symbol)
        }
    }
}

struct AlbumsView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var list = PagedList<Album>()
    @State private var sort: AlbumSort = .title
    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(list.items) { album in
                    NavigationLink(value: Route.album(album.id)) {
                        AlbumTile(album: album)
                    }
                    .buttonStyle(.plain)
                    .task { await list.loadMoreIfNeeded(after: album) }
                }
            }
            .padding()
            if list.isLoading { ProgressView().padding() }
        }
        .overlay { emptyOrError }
        .navigationTitle("Albums")
        .searchable(text: $query, prompt: "Filter albums")
        .toolbar {
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(AlbumSort.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort")
        }
        .task(id: "\(sort.rawValue)|\(query)") {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await reload()
        }
        .refreshable { await reload() }
    }

    private func reload() async {
        let sort = self.sort, query = self.query
        await list.reload(api: session.api) { api, limit, offset in
            try await api.albums(q: query.isEmpty ? nil : query, sort: sort, limit: limit, offset: offset)
        }
    }

    @ViewBuilder private var emptyOrError: some View {
        if list.items.isEmpty, let error = list.error {
            ErrorStateView(error: error) { await reload() }
        } else if list.isEmpty {
            ContentUnavailableView.search(text: query)
        }
    }
}

struct ArtistsView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var list = PagedList<Artist>(pageSize: 100)
    @State private var query = ""

    var body: some View {
        List(list.items) { artist in
            NavigationLink(value: Route.artist(artist.id)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(artist.name)
                    Text("\(Format.count(artist.albumCount, "album")) · \(Format.count(artist.trackCount, "song"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .task { await list.loadMoreIfNeeded(after: artist) }
        }
        .listStyle(.plain)
        .overlay {
            if list.items.isEmpty, let error = list.error {
                ErrorStateView(error: error) { await reload() }
            } else if list.isEmpty {
                ContentUnavailableView.search(text: query)
            } else if list.items.isEmpty && list.isLoading {
                ProgressView()
            }
        }
        .navigationTitle("Artists")
        .searchable(text: $query, prompt: "Filter artists")
        .task(id: query) {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await reload()
        }
        .refreshable { await reload() }
    }

    private func reload() async {
        let query = self.query
        await list.reload(api: session.api) { api, limit, offset in
            try await api.artists(q: query.isEmpty ? nil : query, limit: limit, offset: offset)
        }
    }
}

/// All songs, or the songs of one genre.
struct SongsView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var player: PlayerController
    @StateObject private var list = PagedList<Track>(pageSize: 100)
    let genre: String?

    var body: some View {
        List {
            if !list.items.isEmpty {
                PlayShuffleButtons(tracks: list.items)
                    .listRowSeparator(.hidden)
            }
            ForEach(Array(list.items.enumerated()), id: \.element.id) { offset, track in
                Button {
                    player.play(list.items, startAt: offset)
                } label: {
                    TrackRow(track: track, showsAlbum: true)
                }
                .buttonStyle(.plain)
                .task { await list.loadMoreIfNeeded(after: track) }
            }
        }
        .listStyle(.plain)
        .overlay {
            if list.items.isEmpty, let error = list.error {
                ErrorStateView(error: error) { await reload() }
            } else if list.isEmpty {
                ContentUnavailableView("No songs", systemImage: "music.note")
            } else if list.items.isEmpty && list.isLoading {
                ProgressView()
            }
        }
        .navigationTitle(genre ?? "Songs")
        .task { if list.items.isEmpty { await reload() } }
        .refreshable { await reload() }
    }

    private func reload() async {
        let genre = self.genre
        await list.reload(api: session.api) { api, limit, offset in
            try await api.tracks(genre: genre, sort: genre == nil ? .artist : .album, limit: limit, offset: offset)
        }
    }
}

struct GenresView: View {
    var body: some View {
        LoadingView(load: { try await $0.genres() }) { genres in
            List(genres) { genre in
                NavigationLink(value: Route.songs(genre: genre.name)) {
                    LabeledContent(genre.name, value: "\(genre.trackCount)")
                }
            }
            .overlay {
                if genres.isEmpty { ContentUnavailableView("No genres", systemImage: "guitars") }
            }
        }
        .navigationTitle("Genres")
    }
}

struct FavoritesView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var list = PagedList<Track>(pageSize: 200)

    var body: some View {
        List {
            if !list.items.isEmpty {
                PlayShuffleButtons(tracks: list.items).listRowSeparator(.hidden)
            }
            TrackListSection(tracks: list.items, showsAlbum: true)
            if list.hasMore && !list.items.isEmpty {
                ProgressView().frame(maxWidth: .infinity).task { await list.loadMore() }
            }
        }
        .listStyle(.plain)
        .overlay {
            if list.items.isEmpty, let error = list.error {
                ErrorStateView(error: error) { await reload() }
            } else if list.isEmpty {
                ContentUnavailableView("No favorites yet", systemImage: "heart", description: Text("Tap the heart on a song to save it here."))
            }
        }
        .navigationTitle("Favorites")
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        await list.reload(api: session.api) { api, limit, offset in
            try await api.favorites(limit: limit, offset: offset)
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        LoadingView(load: { try await $0.history(limit: 200) }) { page in
            let tracks = page.items.map(\.track)
            List {
                ForEach(Array(page.items.enumerated()), id: \.element.id) { offset, entry in
                    Button {
                        player.play(tracks, startAt: offset)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            TrackRow(track: entry.track, showsAlbum: true)
                            Text(Format.relative.localizedString(for: entry.playedAt.epochMillisDate, relativeTo: Date()))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 56)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .overlay {
                if page.items.isEmpty {
                    ContentUnavailableView("Nothing played yet", systemImage: "clock")
                }
            }
        }
        .navigationTitle("Recently Played")
    }
}
