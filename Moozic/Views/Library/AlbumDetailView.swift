import SwiftUI

struct AlbumDetailView: View {
    let albumId: Int

    var body: some View {
        LoadingView(load: { try await $0.album(id: albumId) }) { album in
            AlbumContent(album: album)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AlbumContent: View {
    let album: AlbumDetail

    private struct Disc: Identifiable {
        let number: Int?
        let tracks: [Track]
        var id: Int { number ?? -1 }
    }

    /// Tracks come ordered by disc and number; split them into sections only for multi-disc albums.
    private var discs: [Disc] {
        let grouped = Dictionary(grouping: album.tracks, by: \.discNo)
        guard grouped.count > 1 else { return [Disc(number: nil, tracks: album.tracks)] }
        return grouped.keys
            .sorted { ($0 ?? 0) < ($1 ?? 0) }
            .map { Disc(number: $0, tracks: grouped[$0] ?? []) }
    }

    var body: some View {
        // A ScrollView rather than a List: a NavigationLink inside a List row would swallow
        // taps on the Play/Shuffle buttons next to it.
        ScrollView {
            VStack(spacing: 12) {
                CoverArt(path: album.coverUrl, cornerRadius: 10)
                    .frame(maxWidth: 260)
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                VStack(spacing: 4) {
                    Text(album.title).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                    NavigationLink(value: Route.artist(album.artist.id)) {
                        Text(album.artist.name).font(.title3).foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                PlayShuffleButtons(tracks: album.tracks)
            }
            .padding()

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(discs) { disc in
                    if let number = disc.number {
                        Text("Disc \(number)")
                            .font(.headline)
                            .padding(.horizontal)
                            .padding(.top, 16)
                            .padding(.bottom, 4)
                    }
                    ForEach(disc.tracks) { track in
                        AlbumTrackButton(track: track, album: album.tracks)
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .padding(.bottom)
        }
        .navigationTitle(album.title)
        .toolbar {
            Menu {
                TrackMenu(tracks: album.tracks)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var subtitle: String {
        [album.year.map { String($0) }, Format.count(album.trackCount, "song"), Format.longDuration(album.duration)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

/// Plays the whole album from this track.
private struct AlbumTrackButton: View {
    @EnvironmentObject private var player: PlayerController
    let track: Track
    let album: [Track]

    var body: some View {
        Button {
            player.play(album, startAt: album.firstIndex(of: track) ?? 0)
        } label: {
            TrackRow(track: track, leading: .number)
        }
        .buttonStyle(.plain)
    }
}
