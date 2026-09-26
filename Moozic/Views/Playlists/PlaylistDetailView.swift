import SwiftUI

struct PlaylistDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss
    let playlistId: Int

    @State private var playlist: PlaylistDetail? = nil
    @State private var entries: [PlaylistEntry] = []
    @State private var error: Error? = nil
    @State private var actionError: String? = nil
    @State private var showEditor = false
    @State private var confirmDelete = false

    private var tracks: [Track] { entries.map(\.track) }

    var body: some View {
        List {
            if let playlist {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        if let description = playlist.description, !description.isEmpty {
                            Text(description).foregroundStyle(.secondary)
                        }
                        Text(summary(playlist)).font(.subheadline).foregroundStyle(.secondary)
                        PlayShuffleButtons(tracks: tracks)
                    }
                    .listRowSeparator(.hidden)
                }
                Section {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { offset, entry in
                        Button {
                            player.play(tracks, startAt: offset)
                        } label: {
                            TrackRow(track: entry.track, showsAlbum: true)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: playlist.isOwner ? deleteEntries : nil)
                    .onMove(perform: playlist.isOwner ? moveEntries : nil)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if playlist == nil, let error {
                ErrorStateView(error: error) { await load() }
            } else if playlist == nil {
                ProgressView()
            } else if entries.isEmpty {
                ContentUnavailableView("Empty playlist", systemImage: "music.note.list", description: Text("Long-press any song and choose “Add to Playlist…”."))
            }
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .toolbar {
            if let playlist, playlist.isOwner {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showEditor = true } label: { Label("Edit Details", systemImage: "pencil") }
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete Playlist", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            PlaylistEditor(playlist: playlist) { await load() }
        }
        .confirmationDialog("Delete “\(playlist?.name ?? "")”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Playlist", role: .destructive) { Task { await deletePlaylist() } }
        }
        .alert("Couldn't update the playlist", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func summary(_ playlist: PlaylistDetail) -> String {
        var parts = [Format.count(playlist.trackCount, "song"), Format.longDuration(playlist.duration)]
        if !playlist.isOwner, let owner = playlist.owner { parts.insert("by \(owner)", at: 0) }
        if playlist.isPublic { parts.append("Public") }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        guard let api = session.api else { return }
        do {
            let detail = try await api.playlist(id: playlistId)
            playlist = detail
            entries = detail.tracks
            error = nil
        } catch {
            self.error = error
        }
    }

    private func deleteEntries(_ offsets: IndexSet) {
        Task { await remove(offsets) }
    }

    private func moveEntries(_ source: IndexSet, _ destination: Int) {
        Task { await move(source, destination) }
    }

    private func remove(_ offsets: IndexSet) async {
        guard let api = session.api else { return }
        let removed = offsets.map { entries[$0] }
        entries.remove(atOffsets: offsets)
        do {
            for entry in removed { try await api.removeFromPlaylist(id: playlistId, entryId: entry.entryId) }
        } catch {
            actionError = error.localizedDescription
        }
        await load()
    }

    private func move(_ source: IndexSet, _ destination: Int) async {
        guard let api = session.api else { return }
        entries.move(fromOffsets: source, toOffset: destination)
        do {
            try await api.reorderPlaylist(id: playlistId, entryIds: entries.map(\.entryId))
        } catch {
            actionError = error.localizedDescription
            await load()
        }
    }

    private func deletePlaylist() async {
        guard let api = session.api else { return }
        do {
            try await api.deletePlaylist(id: playlistId)
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

/// Sheet for adding tracks to one of your playlists (or a new one).
struct AddToPlaylistView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    let tracks: [Track]

    @State private var playlists: [Playlist]? = nil
    @State private var error: String? = nil
    @State private var showCreate = false
    @State private var adding: Int? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showCreate = true } label: { Label("New Playlist…", systemImage: "plus") }
                }
                Section {
                    ForEach(playlists ?? []) { playlist in
                        Button {
                            Task { await add(to: playlist) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(playlist.name).foregroundStyle(.primary)
                                    Text(Format.count(playlist.trackCount, "song")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if adding == playlist.id { ProgressView() }
                            }
                        }
                        .disabled(adding != nil)
                    }
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }
            .overlay { if playlists == nil && error == nil { ProgressView() } }
            .navigationTitle(tracks.count == 1 ? "Add “\(tracks[0].title)”" : "Add \(tracks.count) Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $showCreate) {
                PlaylistEditor(playlist: nil, initialTrackIds: tracks.map(\.id)) { dismiss() }
            }
            .task {
                do {
                    playlists = try await session.api?.playlists(scope: .mine)
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func add(to playlist: Playlist) async {
        guard let api = session.api else { return }
        adding = playlist.id
        defer { adding = nil }
        do {
            try await api.addToPlaylist(id: playlist.id, trackIds: tracks.map(\.id))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
