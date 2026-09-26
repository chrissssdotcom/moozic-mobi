import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var playlists: [Playlist]? = nil
    @State private var error: Error? = nil
    @State private var showCreate = false

    private var mine: [Playlist] { playlists?.filter(\.isOwner) ?? [] }
    private var shared: [Playlist] { playlists?.filter { !$0.isOwner } ?? [] }

    var body: some View {
        List {
            if !mine.isEmpty {
                Section("My Playlists") {
                    ForEach(mine) { PlaylistRow(playlist: $0) }
                        .onDelete { offsets in
                            let doomed = offsets.map { mine[$0] }
                            Task { await delete(doomed) }
                        }
                }
            }
            if !shared.isEmpty {
                Section("Shared by Others") {
                    ForEach(shared) { PlaylistRow(playlist: $0) }
                }
            }
        }
        .overlay {
            if let error, playlists == nil {
                ErrorStateView(error: error) { await load() }
            } else if playlists == nil {
                ProgressView()
            } else if playlists?.isEmpty == true {
                ContentUnavailableView {
                    Label("No playlists", systemImage: "music.note.list")
                } description: {
                    Text("Create one, or add songs from any list with a long press.")
                } actions: {
                    Button("New Playlist") { showCreate = true }.buttonStyle(.bordered)
                }
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            Button { showCreate = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("New playlist")
        }
        .sheet(isPresented: $showCreate) {
            PlaylistEditor(playlist: nil) { await load() }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let api = session.api else { return }
        do {
            playlists = try await api.playlists()
            error = nil
        } catch {
            self.error = error
        }
    }

    private func delete(_ doomed: [Playlist]) async {
        guard let api = session.api else { return }
        let ids = Set(doomed.map(\.id))
        playlists?.removeAll { ids.contains($0.id) }
        for playlist in doomed { try? await api.deletePlaylist(id: playlist.id) }
        await load()
    }
}

private struct PlaylistRow: View {
    let playlist: Playlist

    var body: some View {
        NavigationLink(value: Route.playlist(playlist.id)) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.gradient)
                    .frame(width: 44, height: 44)
                    .overlay { Image(systemName: "music.note.list").foregroundStyle(.white) }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(playlist.name).lineLimit(1)
                        if playlist.isPublic && playlist.isOwner {
                            Image(systemName: "globe").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private var detail: String {
        var parts = [Format.count(playlist.trackCount, "song")]
        if !playlist.isOwner, let owner = playlist.owner { parts.insert("by \(owner)", at: 0) }
        return parts.joined(separator: " · ")
    }
}

/// Create or edit a playlist's name, description and visibility.
struct PlaylistEditor: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    let playlist: PlaylistDetail?
    var initialTrackIds: [Int] = []
    let onSave: () async -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var isPublic = false
    @State private var saving = false
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(2...5)
                Toggle("Visible to other users", isOn: $isPublic)
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle(playlist == nil ? "New Playlist" : "Edit Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(playlist == nil ? "Create" : "Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .onAppear {
                if let playlist {
                    name = playlist.name
                    description = playlist.description ?? ""
                    isPublic = playlist.isPublic
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        guard let api = session.api else { return }
        saving = true
        defer { saving = false }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let playlist {
                try await api.updatePlaylist(id: playlist.id, name: trimmedName, description: trimmedDescription.isEmpty ? nil : trimmedDescription, isPublic: isPublic)
            } else {
                try await api.createPlaylist(name: trimmedName, description: trimmedDescription.isEmpty ? nil : trimmedDescription, isPublic: isPublic, trackIds: initialTrackIds)
            }
            await onSave()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
