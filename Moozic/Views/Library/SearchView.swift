import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var player: PlayerController
    @State private var query = ""
    @State private var results: SearchResults? = nil
    @State private var error: Error? = nil
    @State private var searching = false

    var body: some View {
        List {
            if let results {
                if !results.artists.isEmpty {
                    Section("Artists") {
                        ForEach(results.artists) { artist in
                            NavigationLink(value: Route.artist(artist.id)) {
                                Label(artist.name, systemImage: "music.mic")
                            }
                        }
                    }
                }
                if !results.albums.isEmpty {
                    Section("Albums") {
                        ForEach(results.albums) { album in
                            NavigationLink(value: Route.album(album.id)) {
                                HStack(spacing: 12) {
                                    CoverArt(path: album.coverUrl, cornerRadius: 4).frame(width: 44, height: 44)
                                    VStack(alignment: .leading) {
                                        Text(album.title).lineLimit(1)
                                        Text(album.artist.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
                if !results.tracks.isEmpty {
                    Section("Songs") {
                        TrackListSection(tracks: results.tracks, showsAlbum: true)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView("Search your library", systemImage: "magnifyingglass", description: Text("Songs, albums and artists."))
            } else if let error {
                ErrorStateView(error: error) { await search() }
            } else if let results, results.isEmpty, !searching {
                ContentUnavailableView.search(text: query)
            } else if results == nil {
                ProgressView()
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Artists, albums, songs")
        .autocorrectionDisabled()
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let api = session.api else {
            results = nil
            error = nil
            return
        }
        searching = true
        defer { searching = false }
        do {
            let found = try await api.search(text, limit: 25)
            guard text == query.trimmingCharacters(in: .whitespaces) else { return }
            results = found
            error = nil
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            self.error = error
        }
    }
}
