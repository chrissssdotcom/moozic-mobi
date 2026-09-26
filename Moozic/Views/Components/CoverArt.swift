import SwiftUI

/// Album cover loaded through the authenticated API, with a placeholder for artwork-less albums.
struct CoverArt: View {
    @EnvironmentObject private var session: SessionStore
    let path: String?
    var cornerRadius: CGFloat = 6

    @State private var image: UIImage? = nil

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.quaternary, lineWidth: 0.5))
            .task(id: path) {
                guard let path, let images = session.images else { image = nil; return }
                if let cached = images.cached(path) { image = cached; return }
                image = nil
                image = await images.image(for: path)
            }
            .accessibilityHidden(true)
    }

    private var placeholder: some View {
        LinearGradient(colors: [Color.accentColor.opacity(0.55), Color.accentColor.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                Image(systemName: "music.note")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.8))
            }
    }
}
