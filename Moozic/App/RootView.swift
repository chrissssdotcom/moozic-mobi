import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            if session.isSignedIn {
                MainTabView()
            } else {
                ConnectView()
            }
        }
        .animation(.default, value: session.isSignedIn)
    }
}

struct MainTabView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: Router

    var body: some View {
        TabView {
            tab { HomeView() }
                .tabItem { Label("Home", systemImage: "house") }
            tab { LibraryView() }
                .tabItem { Label("Library", systemImage: "square.stack") }
            tab { SearchView() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            tab { PlaylistsView() }
                .tabItem { Label("Playlists", systemImage: "music.note.list") }
            tab { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .sheet(isPresented: $router.showNowPlaying) {
            NowPlayingView()
        }
        .sheet(item: $router.playlistPicker) { request in
            AddToPlaylistView(tracks: request.tracks)
        }
        .task { await session.refreshMe() }
    }

    private func tab<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack {
            content().moozicDestinations()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayerView() }
    }
}
