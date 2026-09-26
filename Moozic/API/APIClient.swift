import Foundation

/// Thin client for Moozic's REST API (`/api/v1`).
final class APIClient: @unchecked Sendable {
    let baseURL: URL
    let credentials: CredentialProvider
    private let urlSession: URLSession
    private let onUnauthorized: @Sendable () -> Void

    static let decoder = JSONDecoder()
    static let encoder = JSONEncoder()

    init(baseURL: URL, credentials: CredentialProvider, urlSession: URLSession = .shared, onUnauthorized: @escaping @Sendable () -> Void = {}) {
        self.baseURL = baseURL
        self.credentials = credentials
        self.urlSession = urlSession
        self.onUnauthorized = onUnauthorized
    }

    /// Normalises user input like `music.example.com` or `http://10.0.0.2:3000/` into a base URL.
    static func normalizeServerURL(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false
        else { return nil }
        return url
    }

    /// Absolute URL for an API path such as `/api/v1/albums` (servers may live under a sub-path).
    func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        let base = baseURL.absoluteString.hasSuffix("/") ? String(baseURL.absoluteString.dropLast()) : baseURL.absoluteString
        var components = URLComponents(string: base + (path.hasPrefix("/") ? path : "/" + path))!
        let items = query.filter { $0.value != nil }
        if !items.isEmpty {
            components.queryItems = (components.queryItems ?? []) + items
            // URLComponents leaves "+" alone, but the server's query parser reads it as a space.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        return components.url!
    }

    // MARK: Requests

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try decode(try await perform("GET", path, query: query))
    }

    func send<T: Decodable>(_ method: String, _ path: String, body: (any Encodable)? = nil) async throws -> T {
        try decode(try await perform(method, path, body: body))
    }

    func send(_ method: String, _ path: String, body: (any Encodable)? = nil) async throws {
        _ = try await perform(method, path, body: body)
    }

    /// Raw bytes (cover art). Returns nil on 404 – artwork-less albums are normal.
    func data(_ path: String) async throws -> Data? {
        do {
            return try await perform("GET", path, accept: "image/*").0
        } catch let error as APIError where error.status == 404 {
            return nil
        }
    }

    private func decode<T: Decodable>(_ result: (Data, HTTPURLResponse)) throws -> T {
        do {
            return try Self.decoder.decode(T.self, from: result.0)
        } catch {
            throw APIError.decoding(error)
        }
    }

    @discardableResult
    func perform(_ method: String, _ path: String, query: [URLQueryItem] = [], body: (any Encodable)? = nil, accept: String = "application/json") async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = method
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
        }

        var token: String?
        do {
            token = try await credentials.bearer()
        } catch where APIError.requiresReauthentication(error) {
            onUnauthorized()
            throw APIError.unauthorized(requestId: nil)
        }
        for attempt in 0..<2 {
            if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            if (200..<300).contains(http.statusCode) { return (data, http) }

            let requestId = http.value(forHTTPHeaderField: "X-Request-Id")
            let envelope = try? Self.decoder.decode(ErrorEnvelope.self, from: data)
            switch http.statusCode {
            case 401:
                // Refresh and retry once (per the Moozic mobile-client guide).
                if attempt == 0, let rejected = token {
                    do {
                        token = try await credentials.bearer(rejected: rejected)
                        if token != rejected { continue }
                    } catch where APIError.requiresReauthentication(error) {
                        // fall through to unauthorized
                    }
                }
                onUnauthorized()
                throw APIError.unauthorized(requestId: requestId)
            case 503 where envelope?.error.code == "unavailable":
                throw APIError.unavailable(message: envelope?.error.message ?? "identity provider unreachable", requestId: requestId)
            default:
                throw APIError.server(
                    status: http.statusCode,
                    code: envelope?.error.code ?? "http_\(http.statusCode)",
                    message: envelope?.error.message ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode).capitalized,
                    requestId: requestId
                )
            }
        }
        throw APIError.invalidResponse
    }
}
