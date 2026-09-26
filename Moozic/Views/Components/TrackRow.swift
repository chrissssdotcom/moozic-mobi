import SwiftUI

struct TrackRow: View {
    enum Leading { case number, cover, none }

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var player: PlayerController
    let track: Track
    var leading: Leading = .cover
    var showsAlbum = false

    private var isCurrent: Bool { player.current?.id == track.id }

    var body: some View {
        HStack(spacing: 12) {
            switch leading {
            case .cover:
                CoverArt(path: track.coverUrl, cornerRadius: 4)
                    .frame(width: 44, height: 44)
            case .number:
                Group {
                    if isCurrent {
                        Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint)
                    } else {
                        Text(track.trackNo.map { String($0) } ?? "–").foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline.monospacedDigit())
                .frame(width: 28)
            case .none:
                EmptyView()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Text(showsAlbum ? "\(track.artist.name) · \(track.album.title)" : track.artist.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if session.isFavorite(track) {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.pink)
                    .accessibilityLabel("Favorite")
            }
            Text(Format.duration(track.duration))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .contextMenu { TrackMenu(tracks: [track]) }
    }
}

/// Actions for one or more tracks – used in context menus and "…" menus.
struct TrackMenu: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var router: Router
    let tracks: [Track]

    var body: some View {
        Button { player.playNext(tracks) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
        Button { player.addToQueue(tracks) } label: { Label("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") }
        Button { router.addToPlaylist(tracks) } label: { Label("Add to Playlist…", systemImage: "text.badge.plus") }
        if tracks.count == 1, let track = tracks.first {
            let favorite = session.isFavorite(track)
            Button {
                Task { await session.toggleFavorite(track) }
            } label: {
                Label(favorite ? "Unfavorite" : "Favorite", systemImage: favorite ? "heart.slash" : "heart")
            }
        }
    }
}

/// A list of tracks where tapping one plays the whole list from there.
struct TrackListSection: View {
    @EnvironmentObject private var player: PlayerController
    let tracks: [Track]
    var leading: TrackRow.Leading = .cover
    var showsAlbum = false

    var body: some View {
        ForEach(Array(tracks.enumerated()), id: \.offset) { offset, track in
            Button {
                player.play(tracks, startAt: offset)
            } label: {
                TrackRow(track: track, leading: leading, showsAlbum: showsAlbum)
            }
            .buttonStyle(.plain)
        }
    }
}

/// "Play" and "Shuffle" buttons for a collection.
struct PlayShuffleButtons: View {
    @EnvironmentObject private var player: PlayerController
    let tracks: [Track]

    var body: some View {
        HStack(spacing: 12) {
            Button {
                player.play(tracks)
            } label: {
                Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            Button {
                player.play(tracks, shuffle: true)
            } label: {
                Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(tracks.isEmpty)
    }
}
