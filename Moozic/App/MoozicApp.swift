import SwiftUI

@main
struct MoozicApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var player = PlayerController()
    @StateObject private var router = Router()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(player)
                .environmentObject(router)
                .onAppear { player.attach(session) }
        }
    }
}

/// App-wide presentation state (sheets reachable from any screen).
@MainActor
final class Router: ObservableObject {
    struct PlaylistPickerRequest: Identifiable {
        let id = UUID()
        let tracks: [Track]
    }

    @Published var showNowPlaying = false
    @Published var playlistPicker: PlaylistPickerRequest?

    func addToPlaylist(_ tracks: [Track]) {
        playlistPicker = PlaylistPickerRequest(tracks: tracks)
    }
}

/// Navigation destinations shared by every tab.
enum Route: Hashable {
    case album(Int)
    case artist(Int)
    case playlist(Int)
    case albums
    case artists
    case songs(genre: String?)
    case genres
    case favorites
    case history
}

extension View {
    func moozicDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .album(let id): AlbumDetailView(albumId: id)
            case .artist(let id): ArtistDetailView(artistId: id)
            case .playlist(let id): PlaylistDetailView(playlistId: id)
            case .albums: AlbumsView()
            case .artists: ArtistsView()
            case .songs(let genre): SongsView(genre: genre)
            case .genres: GenresView()
            case .favorites: FavoritesView()
            case .history: HistoryView()
            }
        }
    }
}
