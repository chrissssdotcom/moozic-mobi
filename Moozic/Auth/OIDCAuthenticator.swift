import AuthenticationServices
import Foundation
import UIKit

enum OIDCError: LocalizedError, Equatable {
    case invalidConfiguration(String)
    case cancelled
    case stateMismatch
    case authorizationFailed(String)
    case tokenRequestFailed(status: Int, error: String?, description: String?)
    case noRefreshToken
    case invalidGrant

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): return message
        case .cancelled: return "Sign-in was cancelled."
        case .stateMismatch: return "The sign-in response didn't match the request. Please try again."
        case .authorizationFailed(let message): return "The identity provider refused the sign-in: \(message)"
        case .tokenRequestFailed(let status, let error, let description):
            return "Token request failed (\(status))" + (error.map { ": \($0)" } ?? "") + (description.map { " – \($0)" } ?? "")
        case .noRefreshToken: return "Your session has expired. Please sign in again."
        case .invalidGrant: return "Your session has expired. Please sign in again."
        }
    }
}

/// Authorization Code + PKCE in the system browser (`ASWebAuthenticationSession`), per RFC 8252.
@MainActor
final class OIDCAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func signIn(client: OIDCClientConfig, urlSession: URLSession = .shared) async throws -> OIDCTokens {
        guard let scheme = client.callbackScheme, URL(string: client.redirectURI) != nil else {
            throw OIDCError.invalidConfiguration("The redirect URI “\(client.redirectURI)” is not a valid URL.")
        }
        let pkce = PKCE()
        let state = PKCE.randomURLSafeString(byteCount: 16)
        let nonce = PKCE.randomURLSafeString(byteCount: 16)
        let url = try Self.authorizationURL(client: client, pkce: pkce, state: state, nonce: nonce)

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { url, error in
                if let error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        continuation.resume(throwing: OIDCError.cancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: OIDCError.cancelled)
                }
            }
            session.presentationContextProvider = self
            // Share cookies with Safari so an existing IdP session gives one-tap sign-in.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: OIDCError.invalidConfiguration("Couldn't open the sign-in page."))
            }
        }
        session = nil

        let code = try Self.authorizationCode(from: callback, expectedState: state)
        return try await TokenClient.exchange(code: code, verifier: pkce.verifier, client: client, urlSession: urlSession)
    }

    nonisolated static func authorizationURL(client: OIDCClientConfig, pkce: PKCE, state: String, nonce: String) throws -> URL {
        guard var components = URLComponents(url: client.authorizationEndpoint, resolvingAgainstBaseURL: false) else {
            throw OIDCError.invalidConfiguration("Invalid authorization endpoint.")
        }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: client.clientId),
            URLQueryItem(name: "redirect_uri", value: client.redirectURI),
            URLQueryItem(name: "scope", value: client.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
        ]
        guard let url = components.url else { throw OIDCError.invalidConfiguration("Invalid authorization endpoint.") }
        return url
    }

    nonisolated static func authorizationCode(from callback: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw OIDCError.authorizationFailed(value("error_description") ?? error)
        }
        guard value("state") == expectedState else { throw OIDCError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else {
            throw OIDCError.authorizationFailed("no authorization code in the response")
        }
        return code
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let windows = scenes.flatMap(\.windows)
            if let key = windows.first(where: \.isKeyWindow) ?? windows.first { return key }
            return ASPresentationAnchor(windowScene: scenes.first!)
        }
    }
}

/// Token endpoint calls (RFC 6749 §4.1.3 and §6).
enum TokenClient {
    private struct TokenResponse: Decodable {
        let access_token: String
        let id_token: String?
        let refresh_token: String?
        let expires_in: Double?
    }

    private struct TokenErrorResponse: Decodable {
        let error: String?
        let error_description: String?
    }

    static func exchange(code: String, verifier: String, client: OIDCClientConfig, urlSession: URLSession) async throws -> OIDCTokens {
        try await request(client.tokenEndpoint, [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": client.redirectURI,
            "client_id": client.clientId,
            "code_verifier": verifier,
        ], urlSession: urlSession)
    }

    static func refresh(_ tokens: OIDCTokens, client: OIDCClientConfig, urlSession: URLSession = .shared) async throws -> OIDCTokens {
        guard let refreshToken = tokens.refreshToken else { throw OIDCError.noRefreshToken }
        let fresh = try await request(client.tokenEndpoint, [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": client.clientId,
        ], urlSession: urlSession)
        return tokens.merged(with: fresh)
    }

    static func formBody(_ params: [String: String]) -> Data {
        // RFC 3986 unreserved characters only (CharacterSet.alphanumerics would let non-ASCII letters through).
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let body = params
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private static func request(_ url: URL, _ params: [String: String], urlSession: URLSession) async throws -> OIDCTokens {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formBody(params)

        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let err = try? JSONDecoder().decode(TokenErrorResponse.self, from: data)
            if err?.error == "invalid_grant" { throw OIDCError.invalidGrant }
            throw OIDCError.tokenRequestFailed(status: status, error: err?.error, description: err?.error_description)
        }
        let body = try JSONDecoder().decode(TokenResponse.self, from: data)
        return OIDCTokens(
            accessToken: body.access_token,
            idToken: body.id_token,
            refreshToken: body.refresh_token,
            accessTokenExpiresAt: body.expires_in.map { Date().addingTimeInterval($0) }
        )
    }
}
