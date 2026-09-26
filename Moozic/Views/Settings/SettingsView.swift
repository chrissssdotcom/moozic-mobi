import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @AppStorage(StreamQuality.storageKey) private var quality: StreamQuality = .original
    @State private var serverVersion: String? = nil
    @State private var confirmSignOut = false

    var body: some View {
        Form {
            Section("Account") {
                if let me = session.me {
                    LabeledContent("Name", value: me.displayName)
                    if let email = me.email { LabeledContent("Email", value: email) }
                    if me.isAdmin { LabeledContent("Role", value: "Administrator") }
                }
                if let account = session.account {
                    LabeledContent("Signed in with", value: account.credential.label)
                }
            }

            Section("Server") {
                if let account = session.account {
                    LabeledContent("Address", value: account.serverURL.absoluteString)
                }
                if let serverVersion { LabeledContent("Version", value: serverVersion) }
            }

            Section {
                Picker("Streaming quality", selection: $quality) {
                    ForEach(StreamQuality.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Playback")
            } footer: {
                Text("Transcoding saves mobile data but needs ffmpeg on the server, and transcoded tracks can't be scrubbed. Applies from the next track.")
            }

            if session.account?.credential.isAnonymous == false {
                Section {
                    NavigationLink("API Tokens") { APITokensView() }
                } footer: {
                    Text("Personal tokens for scripts and other apps.")
                }
            }

            Section {
                Button("Sign Out", role: .destructive) { confirmSignOut = true }
            }

            Section {
                LabeledContent("App version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Sign out of this server?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { session.signOut() }
        }
        .task {
            serverVersion = try? await session.api?.health().version
            await session.refreshMe()
        }
    }
}

private struct APITokensView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var tokens: [ApiToken]? = nil
    @State private var error: String? = nil
    @State private var newName = ""
    @State private var created: NewApiToken? = nil

    var body: some View {
        Form {
            if let created {
                Section {
                    Text(created.token)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = created.token
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                } header: {
                    Text("New token “\(created.name)”")
                } footer: {
                    Text("Copy it now – it won't be shown again.")
                }
            }

            Section("Create") {
                TextField("Name, e.g. Home Assistant", text: $newName)
                Button("Create Token") { Task { await create() } }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section("Your tokens") {
                if let tokens {
                    if tokens.isEmpty { Text("None").foregroundStyle(.secondary) }
                    ForEach(tokens) { token in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(token.name)
                                if token.id == session.account?.mediaToken?.id {
                                    Text("this device").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(.tint.opacity(0.15), in: Capsule())
                                }
                            }
                            Text(caption(token)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        let doomed = offsets.map { tokens[$0] }
                        Task { await revoke(doomed) }
                    }
                } else {
                    ProgressView()
                }
            }

            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("API Tokens")
        .task { await load() }
    }

    private func caption(_ token: ApiToken) -> String {
        var parts = ["\(token.prefix)…"]
        if let used = token.lastUsedAt {
            parts.append("used " + Format.relative.localizedString(for: used.epochMillisDate, relativeTo: Date()))
        } else {
            parts.append("never used")
        }
        if let expires = token.expiresAt {
            parts.append("expires " + expires.epochMillisDate.formatted(date: .abbreviated, time: .omitted))
        }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        do {
            tokens = try await session.api?.apiTokens()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func create() async {
        guard let api = session.api else { return }
        do {
            created = try await api.createAPIToken(name: newName.trimmingCharacters(in: .whitespaces))
            newName = ""
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func revoke(_ doomed: [ApiToken]) async {
        guard let api = session.api else { return }
        for token in doomed {
            do { try await api.deleteAPIToken(id: token.id) } catch { self.error = error.localizedDescription }
        }
        await load()
    }
}
