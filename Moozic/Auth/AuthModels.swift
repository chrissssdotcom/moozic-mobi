import Foundation

/// `GET /api/v1/auth/config` – how the server wants clients to sign in.
struct AuthConfig: Codable, Equatable {
    let mode: String
    let issuer: String?
    let discoveryUrl: String?
    let authorizationEndpoint: String?
    let tokenEndpoint: String?
    let endSessionEndpoint: String?
    let clientIds: [String]?
    let scopes: [String]?
    let pkce: String?
    let apiTokens: Bool?

    var isAuthDisabled: Bool { mode == "disabled" }
    var supportsOIDC: Bool { mode == "oidc" && authorizationEndpoint != nil && tokenEndpoint != nil }

    /// Best guess at the client id registered for native apps: one mentioning
    /// ios/mobile/app/native, else the last listed (the server lists its own web client first).
    var suggestedClientId: String? {
        guard let ids = clientIds, !ids.isEmpty else { return nil }
        let hints = ["ios", "mobile", "native", "app"]
        for hint in hints {
            if let match = ids.first(where: { $0.lowercased().contains(hint) }) { return match }
        }
        return ids.last
    }
}

/// Everything needed to run the authorization-code flow against the IdP and refresh later.
struct OIDCClientConfig: Codable, Equatable {
    var clientId: String
    var redirectURI: String
    var scopes: [String]
    var authorizationEndpoint: URL
    var tokenEndpoint: URL
    var endSessionEndpoint: URL?

    static let defaultRedirectURI = "com.chrissss.moozic:/oauth2redirect"

    var callbackScheme: String? { URL(string: redirectURI)?.scheme }
}

/// Tokens from the identity provider.
struct OIDCTokens: Codable, Equatable {
    var accessToken: String
    var idToken: String?
    var refreshToken: String?
    /// Expiry of the access token as reported by `expires_in`.
    var accessTokenExpiresAt: Date?

    /// Moozic only accepts JWTs. Prefer the access token; if the IdP issues opaque
    /// access tokens, fall back to the ID token (also accepted by the server).
    var bearer: String {
        if JWT.isJWT(accessToken) { return accessToken }
        return idToken ?? accessToken
    }

    var bearerExpiresAt: Date? {
        JWT.expiry(of: bearer) ?? (bearer == accessToken ? accessTokenExpiresAt : nil)
    }

    func needsRefresh(now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        guard let exp = bearerExpiresAt else { return false }
        return exp.timeIntervalSince(now) < leeway
    }

    /// Merge a refresh response: IdPs may omit tokens that didn't rotate.
    func merged(with newer: OIDCTokens) -> OIDCTokens {
        OIDCTokens(
            accessToken: newer.accessToken,
            idToken: newer.idToken ?? idToken,
            refreshToken: newer.refreshToken ?? refreshToken,
            accessTokenExpiresAt: newer.accessTokenExpiresAt
        )
    }
}

/// A long-lived personal token (`mzk_…`) used for audio streams, so playback of a long
/// queue survives short-lived OIDC access tokens.
struct MediaToken: Codable, Equatable {
    /// Server-side id when the app created the token itself (revoked on sign-out); nil when user-supplied.
    var id: Int?
    var token: String
}

enum Credential: Codable, Equatable {
    /// Server runs with `AUTH_MODE=disabled`.
    case anonymous
    /// Personal API token pasted by the user.
    case apiToken(String)
    /// Signed in through the identity provider.
    case oidc(OIDCTokens, OIDCClientConfig)

    var label: String {
        switch self {
        case .anonymous: return "No authentication"
        case .apiToken: return "Personal API token"
        case .oidc: return "Single sign-on (OIDC)"
        }
    }

    var isAnonymous: Bool {
        if case .anonymous = self { return true }
        return false
    }
}

/// Persisted (in the Keychain) connection to one Moozic server.
struct Account: Codable, Equatable {
    var serverURL: URL
    var credential: Credential
    var mediaToken: MediaToken?
}

/// Minimal JWT inspection – no verification (the server does that), just reading claims.
enum JWT {
    static func isJWT(_ token: String) -> Bool {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && claims(of: token) != nil
    }

    static func claims(of token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let data = Data(base64URLEncoded: String(parts[1])),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    static func expiry(of token: String) -> Date? {
        guard let exp = claims(of: token)?["exp"] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: exp.doubleValue)
    }
}
