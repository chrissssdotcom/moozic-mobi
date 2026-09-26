import Foundation

/// Hands out the `Authorization` header for API calls, refreshing OIDC tokens when they
/// are about to expire. Concurrent callers share a single in-flight refresh.
actor CredentialProvider {
    private(set) var credential: Credential
    private var refreshTask: Task<OIDCTokens, Error>?
    private let urlSession: URLSession
    private let onChange: @Sendable (Credential) -> Void

    init(credential: Credential, urlSession: URLSession = .shared, onChange: @escaping @Sendable (Credential) -> Void = { _ in }) {
        self.credential = credential
        self.urlSession = urlSession
        self.onChange = onChange
    }

    /// The bearer token to send, or nil when the server needs none.
    /// - Parameter rejected: a token the server just answered `401` to; forces a refresh if it's still current.
    func bearer(rejected: String? = nil) async throws -> String? {
        switch credential {
        case .anonymous:
            return nil
        case .apiToken(let token):
            return token
        case .oidc(let tokens, let client):
            let mustRefresh = tokens.needsRefresh() || (rejected != nil && rejected == tokens.bearer)
            guard mustRefresh else { return tokens.bearer }
            if rejected == nil, tokens.refreshToken == nil, let exp = tokens.bearerExpiresAt, exp > Date() {
                // Close to expiry but nothing to refresh with: use it while it lasts.
                return tokens.bearer
            }
            return try await refreshed(tokens, client: client).bearer
        }
    }

    private func refreshed(_ tokens: OIDCTokens, client: OIDCClientConfig) async throws -> OIDCTokens {
        if let refreshTask { return try await refreshTask.value }
        let session = urlSession
        let task = Task { try await TokenClient.refresh(tokens, client: client, urlSession: session) }
        refreshTask = task
        defer { refreshTask = nil }
        let fresh = try await task.value
        credential = .oidc(fresh, client)
        onChange(credential)
        return fresh
    }
}
