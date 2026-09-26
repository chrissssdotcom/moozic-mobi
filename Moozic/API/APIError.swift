import Foundation

/// `{ "error": { "code", "message", "details"? } }`
struct ErrorEnvelope: Decodable {
    struct Body: Decodable {
        struct Detail: Decodable { let path: String; let message: String }
        let code: String
        let message: String
        let details: [Detail]?
    }
    let error: Body
}

enum APIError: LocalizedError {
    /// Credentials were rejected even after a refresh; the user must sign in again.
    case unauthorized(requestId: String?)
    /// `503 unavailable`: the server can't reach the identity provider. Retry later, don't sign out.
    case unavailable(message: String, requestId: String?)
    /// Any other error response from the server.
    case server(status: Int, code: String, message: String, requestId: String?)
    case invalidResponse
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Your session has expired. Please sign in again."
        case .unavailable(let message, _): return "The server can't verify your sign-in right now (\(message)). Try again shortly."
        case .server(_, _, let message, _): return message
        case .invalidResponse: return "The server sent an unexpected response."
        case .decoding(let error): return "Couldn't read the server's response: \(error.localizedDescription)"
        }
    }

    var code: String? {
        if case .server(_, let code, _, _) = self { return code }
        return nil
    }

    var status: Int? {
        switch self {
        case .unauthorized: return 401
        case .unavailable: return 503
        case .server(let status, _, _, _): return status
        default: return nil
        }
    }

    var requestId: String? {
        switch self {
        case .unauthorized(let id), .unavailable(_, let id), .server(_, _, _, let id): return id
        default: return nil
        }
    }

    /// Whether the user has to sign in again (as opposed to a transient failure).
    static func requiresReauthentication(_ error: Error) -> Bool {
        if case APIError.unauthorized = error { return true }
        if let error = error as? OIDCError, error == .invalidGrant || error == .noRefreshToken { return true }
        return false
    }
}
