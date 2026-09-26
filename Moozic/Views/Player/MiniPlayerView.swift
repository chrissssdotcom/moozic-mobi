import SwiftUI

/// Compact player shown above the tab bar on every tab.
struct MiniPlayerView: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var router: Router

    var body: some View {
        if let track = player.current {
            VStack(spacing: 0) {
                ProgressView(value: player.duration > 0 ? min(player.elapsed / player.duration, 1) : 0)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .scaleEffect(x: 1, y: 0.6, anchor: .top)
                HStack(spacing: 12) {
                    CoverArt(path: track.coverUrl, cornerRadius: 4)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(player.errorMessage ?? track.artist.name)
                            .font(.caption)
                            .foregroundStyle(player.errorMessage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                    Button {
                        player.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Next track")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
            .contentShape(Rectangle())
            .onTapGesture { router.showNowPlaying = true }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isButton)
        }
    }
}
