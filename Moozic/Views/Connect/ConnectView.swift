import SwiftUI

/// First run: enter the server, discover its auth setup, then sign in with the IdP or a personal token.
struct ConnectView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var serverText = ""
    @State private var server: URL? = nil
    @State private var config: AuthConfig? = nil
    @State private var busy = false
    @State private var error: String? = nil

    // OIDC
    @State private var clientId = ""
    @State private var redirectURI = OIDCClientConfig.defaultRedirectURI
    @State private var offlineAccess = true
    @State private var showAdvanced = false

    // API token
    @State private var apiToken = ""
    @State private var useToken = false

    var body: some View {
        NavigationStack {
            Form {
                header

                if let reason = session.signedOutReason {
                    Section { Label(reason, systemImage: "clock.badge.exclamationmark").foregroundStyle(.orange) }
                }

                Section {
                    TextField("music.example.com", text: $serverText)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.continue)
                        .onSubmit { Task { await discover() } }
                        .onChange(of: serverText) { _, _ in
                            if config != nil { config = nil; server = nil }
                        }
                    if config == nil {
                        Button {
                            Task { await discover() }
                        } label: {
                            HStack {
                                Text("Continue")
                                if busy { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(busy || APIClient.normalizeServerURL(serverText) == nil)
                    }
                } header: {
                    Text("Server")
                } footer: {
                    Text("The address of your Moozic server, e.g. https://music.example.com or http://192.168.1.10:3000.")
                }

                if let config, let server {
                    if config.isAuthDisabled {
                        disabledAuthSection(server)
                    } else {
                        if config.supportsOIDC && !useToken {
                            oidcSection(config, server)
                        }
                        if useToken || !config.supportsOIDC {
                            tokenSection(server)
                        }
                        if config.supportsOIDC && config.apiTokens != false {
                            Section {
                                Button(useToken ? "Sign in with single sign-on instead" : "Use a personal API token instead") {
                                    useToken.toggle()
                                    error = nil
                                }
                            }
                        }
                    }
                }

                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
            }
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(busy)
            .onAppear {
                if serverText.isEmpty { serverText = session.lastServerURL }
            }
        }
    }

    private var header: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "music.note.house.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("Moozic").font(.largeTitle.weight(.bold))
                Text("Your self-hosted music, anywhere.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .listRowBackground(Color.clear)
    }

    private func disabledAuthSection(_ server: URL) -> some View {
        Section {
            Button {
                run { try await session.connectWithoutAuth(server: server) }
            } label: {
                Label("Connect", systemImage: "arrow.right.circle.fill")
            }
        } footer: {
            Text("This server runs without authentication (development mode).")
        }
    }

    @ViewBuilder
    private func oidcSection(_ config: AuthConfig, _ server: URL) -> some View {
        Section {
            Button {
                signInWithOIDC(config, server)
            } label: {
                Label("Sign in", systemImage: "person.badge.key.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .disabled(clientId.isEmpty)
        } header: {
            Text("Single sign-on")
        } footer: {
            if let issuer = config.issuer {
                Text("You'll sign in at \(URL(string: issuer)?.host ?? issuer) in a secure browser window.")
            }
        }

        Section {
            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                if let ids = config.clientIds, ids.count > 1 {
                    Picker("Client ID", selection: $clientId) {
                        ForEach(ids, id: \.self) { Text($0).tag($0) }
                    }
                } else {
                    LabeledContent("Client ID") {
                        TextField("moozic-mobile", text: $clientId)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Redirect URI").font(.caption).foregroundStyle(.secondary)
                    TextField(OIDCClientConfig.defaultRedirectURI, text: $redirectURI)
                        .font(.callout.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Toggle("Request offline access", isOn: $offlineAccess)
            }
        } footer: {
            Text("Register a public client with this redirect URI at your identity provider and add its client ID to the server's OIDC_ALLOWED_AUDIENCES. Offline access asks for a refresh token so you stay signed in.")
        }
    }

    private func tokenSection(_ server: URL) -> some View {
        Section {
            SecureField("mzk_…", text: $apiToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
            Button {
                run { try await session.connect(server: server, apiToken: apiToken) }
            } label: {
                Label("Connect with token", systemImage: "key.fill")
            }
            .disabled(apiToken.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("Personal API token")
        } footer: {
            Text("Create one in Moozic's web app under Settings → API access.")
        }
    }

    // MARK: Actions

    private func discover() async {
        guard let url = APIClient.normalizeServerURL(serverText) else {
            error = "That doesn't look like a server address."
            return
        }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let config = try await APIClient.fetchAuthConfig(server: url)
            self.server = url
            self.config = config
            configureDefaults(for: config, server: url)
        } catch {
            self.error = "Couldn't reach a Moozic server at \(url.absoluteString): \(error.localizedDescription)"
        }
    }

    private func configureDefaults(for config: AuthConfig, server: URL) {
        useToken = !config.supportsOIDC
        let last = session.lastClientConfig
        let sameServer = session.lastServerURL == server.absoluteString
        if sameServer, let last {
            clientId = last.clientId
            redirectURI = last.redirectURI
            offlineAccess = last.scopes.contains("offline_access")
        } else {
            clientId = config.suggestedClientId ?? ""
        }
        // Surface the settings when there's something to decide.
        showAdvanced = clientId.isEmpty || (config.clientIds?.count ?? 0) > 1 && !sameServer
    }

    private func signInWithOIDC(_ config: AuthConfig, _ server: URL) {
        guard let authorization = config.authorizationEndpoint.flatMap({ URL(string: $0) }),
              let token = config.tokenEndpoint.flatMap({ URL(string: $0) })
        else {
            error = "The server didn't provide the identity provider's endpoints."
            return
        }
        var scopes = config.scopes ?? ["openid", "profile", "email"]
        if offlineAccess && !scopes.contains("offline_access") { scopes.append("offline_access") }
        let client = OIDCClientConfig(
            clientId: clientId.trimmingCharacters(in: .whitespaces),
            redirectURI: redirectURI.trimmingCharacters(in: .whitespaces),
            scopes: scopes,
            authorizationEndpoint: authorization,
            tokenEndpoint: token,
            endSessionEndpoint: config.endSessionEndpoint.flatMap({ URL(string: $0) })
        )
        run { try await session.signInWithOIDC(server: server, client: client) }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await action()
            } catch OIDCError.cancelled {
                // user closed the browser
            } catch let apiError as APIError where apiError.status == 401 {
                error = "The server rejected the credentials. " + (useToken
                    ? "Check the token hasn't expired or been revoked."
                    : "Make sure the client ID “\(clientId)” is in the server's OIDC_ALLOWED_AUDIENCES and the IdP issues JWT access tokens.")
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
