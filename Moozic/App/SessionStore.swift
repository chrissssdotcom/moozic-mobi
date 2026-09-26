import Foundation
import UIKit

/// Owns the signed-in account, the API client built from it, and user-level state
/// shared across screens (favorites overrides, the current user).
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var account: Account?
    @Published private(set) var api: APIClient?
    @Published private(set) var images: ImageLoader?
    @Published private(set) var me: Me?
    /// Shown on the connect screen after the session expired.
    @Published var signedOutReason: String?
    /// Local favorite changes, so every list reflects a toggle without refetching.
    @Published private var favoriteOverrides: [Int: Bool] = [:]

    /// Server URL and OIDC client settings of the last account, to prefill the connect screen.
    @Published private(set) var lastServerURL: String = UserDefaults.standard.string(forKey: "lastServerURL") ?? ""
    private(set) var lastClientConfig: OIDCClientConfig? = {
        guard let data = UserDefaults.standard.data(forKey: "lastClientConfig") else { return nil }
        return try? JSONDecoder().decode(OIDCClientConfig.self, from: data)
    }()

    private let authenticator = OIDCAuthenticator()

    init() {
        if let saved = AccountStore.load() { activate(saved) }
    }

    var isSignedIn: Bool { account != nil }

    // MARK: Connecting

    func connectWithoutAuth(server: URL) async throws {
        try await finishSignIn(Account(serverURL: server, credential: .anonymous))
    }

    func connect(server: URL, apiToken: String) async throws {
        let token = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        try await finishSignIn(Account(serverURL: server, credential: .apiToken(token), mediaToken: MediaToken(id: nil, token: token)))
    }

    func signInWithOIDC(server: URL, client: OIDCClientConfig) async throws {
        let tokens = try await authenticator.signIn(client: client)
        UserDefaults.standard.set(try? JSONEncoder().encode(client), forKey: "lastClientConfig")
        lastClientConfig = client
        try await finishSignIn(Account(serverURL: server, credential: .oidc(tokens, client)))
    }

    /// Verifies the credential with `GET /me`, then persists and activates the account.
    private func finishSignIn(_ candidate: Account) async throws {
        var account = candidate
        let probe = makeClient(for: account, persistChanges: false)
        let me = try await probe.me()

        if case .oidc = account.credential {
            // Streams outlive short OIDC access tokens, so give the player its own personal token.
            let name = "Moozic iOS – \(UIDevice.current.name)"
            if let created = try? await probe.createAPIToken(name: name) {
                account.mediaToken = MediaToken(id: created.id, token: created.token)
            }
            // Pick up tokens the probe may have refreshed.
            account.credential = await probe.credentials.credential
        }

        AccountStore.save(account)
        UserDefaults.standard.set(account.serverURL.absoluteString, forKey: "lastServerURL")
        lastServerURL = account.serverURL.absoluteString
        signedOutReason = nil
        activate(account)
        self.me = me
    }

    private func activate(_ account: Account) {
        self.account = account
        let client = makeClient(for: account, persistChanges: true)
        api = client
        images = ImageLoader(api: client)
        favoriteOverrides = [:]
    }

    private func makeClient(for account: Account, persistChanges: Bool) -> APIClient {
        let credentials = CredentialProvider(credential: account.credential) { [weak self] updated in
            guard persistChanges else { return }
            Task { @MainActor in self?.credentialDidChange(updated) }
        }
        return APIClient(baseURL: account.serverURL, credentials: credentials) { [weak self] in
            guard persistChanges else { return }
            Task { @MainActor in self?.sessionExpired() }
        }
    }

    private func credentialDidChange(_ credential: Credential) {
        guard var account else { return }
        account.credential = credential
        self.account = account
        AccountStore.save(account)
    }

    func refreshMe() async {
        guard let api else { return }
        if let me = try? await api.me() { self.me = me }
    }

    // MARK: Signing out

    private func sessionExpired() {
        guard account != nil else { return }
        signOut(reason: "Your session expired. Please sign in again.", revokeMediaToken: false)
    }

    func signOut(reason: String? = nil, revokeMediaToken: Bool = true) {
        if revokeMediaToken, let api, let id = account?.mediaToken?.id {
            Task { try? await api.deleteAPIToken(id: id) }
        }
        AccountStore.delete()
        account = nil
        api = nil
        images = nil
        me = nil
        favoriteOverrides = [:]
        signedOutReason = reason
        NotificationCenter.default.post(name: .moozicDidSignOut, object: nil)
    }

    // MARK: Favorites

    func isFavorite(_ track: Track) -> Bool {
        favoriteOverrides[track.id] ?? track.favorite
    }

    func toggleFavorite(_ track: Track) async {
        guard let api else { return }
        let newValue = !isFavorite(track)
        favoriteOverrides[track.id] = newValue
        do {
            try await api.setFavorite(trackId: track.id, newValue)
        } catch {
            favoriteOverrides[track.id] = !newValue
        }
    }

    // MARK: Media

    /// Headers for AVPlayer requests. Uses the long-lived media token when there is one.
    func mediaHeaders() async -> [String: String] {
        if let token = account?.mediaToken?.token { return ["Authorization": "Bearer \(token)"] }
        guard let bearer = try? await api?.credentials.bearer() else { return [:] }
        return ["Authorization": "Bearer \(bearer)"]
    }
}

extension Notification.Name {
    static let moozicDidSignOut = Notification.Name("moozicDidSignOut")
}
