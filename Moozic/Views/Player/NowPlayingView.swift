import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss

    @State private var scrubbing: Double? = nil
    @State private var showQueue = false

    var body: some View {
        NavigationStack {
            Group {
                if let track = player.current {
                    content(track)
                } else {
                    ContentUnavailableView("Nothing playing", systemImage: "music.note", description: Text("Pick an album or a song to start listening."))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showQueue = true } label: { Image(systemName: "list.bullet") }
                        .accessibilityLabel("Queue")
                        .disabled(player.queue.isEmpty)
                }
            }
            .sheet(isPresented: $showQueue) { QueueView() }
        }
    }

    private func content(_ track: Track) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            CoverArt(path: track.coverUrl, cornerRadius: 12)
                .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
                .scaleEffect(player.isPlaying ? 1 : 0.9)
                .animation(.spring(duration: 0.4), value: player.isPlaying)
                .padding(.horizontal, 12)
                .frame(maxWidth: 420)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title).font(.title2.weight(.bold)).lineLimit(2)
                    Text(track.artist.name).font(.title3).foregroundStyle(.secondary).lineLimit(1)
                    Text(track.album.title).font(.subheadline).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer()
                let favorite = session.isFavorite(track)
                Button {
                    Task { await session.toggleFavorite(track) }
                } label: {
                    Image(systemName: favorite ? "heart.fill" : "heart")
                        .font(.title2)
                        .foregroundStyle(favorite ? AnyShapeStyle(.pink) : AnyShapeStyle(.secondary))
                }
                .accessibilityLabel(favorite ? "Unfavorite" : "Favorite")
                Menu {
                    TrackMenu(tracks: [track])
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title2)
                }
            }

            if let error = player.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { scrubbing ?? player.elapsed },
                        set: { scrubbing = $0 }
                    ),
                    in: 0...max(player.duration, 1),
                    onEditingChanged: { editing in
                        if !editing, let target = scrubbing {
                            player.seek(to: target)
                            scrubbing = nil
                        }
                    }
                )
                .disabled(!player.canSeek)
                HStack {
                    Text(Format.duration(scrubbing ?? player.elapsed))
                    Spacer()
                    if player.isBuffering { ProgressView().controlSize(.mini) }
                    Spacer()
                    Text("-" + Format.duration(max(player.duration - (scrubbing ?? player.elapsed), 0)))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            HStack {
                Button { player.toggleShuffle() } label: {
                    Image(systemName: "shuffle")
                        .foregroundStyle(player.isShuffled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                .accessibilityLabel(player.isShuffled ? "Shuffle on" : "Shuffle off")
                Spacer()
                Button { player.previous() } label: { Image(systemName: "backward.fill").font(.title) }
                    .accessibilityLabel("Previous")
                Spacer()
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Spacer()
                Button { player.next() } label: { Image(systemName: "forward.fill").font(.title) }
                    .accessibilityLabel("Next")
                Spacer()
                Button { player.repeatMode = player.repeatMode.next } label: {
                    Image(systemName: player.repeatMode.symbol)
                        .foregroundStyle(player.repeatMode == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                }
                .accessibilityLabel("Repeat \(player.repeatMode.rawValue)")
            }
            .buttonStyle(.plain)
            .font(.title3)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
}

struct QueueView: View {
    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(player.queue.enumerated()), id: \.offset) { offset, track in
                    Button {
                        player.jump(to: offset)
                    } label: {
                        HStack {
                            TrackRow(track: track)
                            if offset == player.index {
                                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { player.removeFromQueue(at: $0) }
                .onMove { player.moveInQueue(from: $0, to: $1) }
            }
            .listStyle(.plain)
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
