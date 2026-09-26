import XCTest
@testable import Moozic

/// Answers requests from a handler instead of the network.
final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, [String: String], Data))?
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = self.request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            request.httpBody = data
        }
        Self.requests.append(request)
        let (status, headers, body) = Self.handler?(request) ?? (500, [:], Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class APIClientTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: config)
        StubURLProtocol.requests = []
        StubURLProtocol.handler = nil
    }

    private func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }

    func testNormalizeServerURL() {
        XCTAssertEqual(APIClient.normalizeServerURL("music.example.com")?.absoluteString, "https://music.example.com")
        XCTAssertEqual(APIClient.normalizeServerURL(" http://10.0.0.2:3000/ ")?.absoluteString, "http://10.0.0.2:3000")
        XCTAssertEqual(APIClient.normalizeServerURL("https://x.org/moozic//")?.absoluteString, "https://x.org/moozic")
        XCTAssertNil(APIClient.normalizeServerURL(""))
        XCTAssertNil(APIClient.normalizeServerURL("ftp://x.org"))
    }

    func testURLBuildingKeepsSubPathAndEncodesPlus() {
        let api = APIClient(baseURL: URL(string: "https://x.org/moozic")!, credentials: CredentialProvider(credential: .anonymous))
        XCTAssertEqual(api.url("/api/v1/albums/3/cover").absoluteString, "https://x.org/moozic/api/v1/albums/3/cover")
        let search = api.url("/api/v1/search", query: [URLQueryItem(name: "q", value: "a+b c"), URLQueryItem(name: "skip", value: nil)])
        XCTAssertEqual(search.absoluteString, "https://x.org/moozic/api/v1/search?q=a%2Bb%20c")
    }

    func testSendsBearerAndDecodes() async throws {
        StubURLProtocol.handler = { _ in
            (200, ["Content-Type": "application/json"], self.json(["id": 1, "username": "chris", "email": NSNull(), "name": "Chris", "isAdmin": true, "authMethod": "api_token"]))
        }
        let api = APIClient(baseURL: URL(string: "https://m.test")!, credentials: CredentialProvider(credential: .apiToken("mzk_x")), urlSession: session)
        let me = try await api.me()
        XCTAssertEqual(me.displayName, "Chris")
        XCTAssertTrue(me.isAdmin)
        XCTAssertEqual(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer mzk_x")
    }

    func testErrorEnvelopeBecomesServerError() async {
        StubURLProtocol.handler = { _ in
            (404, ["X-Request-Id": "req-1"], self.json(["error": ["code": "not_found", "message": "Album not found"]]))
        }
        let api = APIClient(baseURL: URL(string: "https://m.test")!, credentials: CredentialProvider(credential: .anonymous), urlSession: session)
        do {
            _ = try await api.album(id: 9)
            XCTFail("expected an error")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 404)
            XCTAssertEqual(error.code, "not_found")
            XCTAssertEqual(error.requestId, "req-1")
            XCTAssertEqual(error.errorDescription, "Album not found")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testRejectedAPITokenReportsUnauthorized() async {
        StubURLProtocol.handler = { _ in (401, ["WWW-Authenticate": "Bearer"], self.json(["error": ["code": "unauthorized", "message": "no"]])) }
        let expectation = expectation(description: "onUnauthorized")
        let api = APIClient(baseURL: URL(string: "https://m.test")!, credentials: CredentialProvider(credential: .apiToken("mzk_bad")), urlSession: session) {
            expectation.fulfill()
        }
        do {
            _ = try await api.me()
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(APIError.requiresReauthentication(error))
        }
        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(StubURLProtocol.requests.count, 1, "an API token can't be refreshed, so no retry")
    }

    func testOIDCTokenIsRefreshedAndRequestRetriedOn401() async throws {
        StubURLProtocol.handler = { request in
            if request.url?.host == "idp.test" {
                let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                XCTAssertTrue(body.contains("grant_type=refresh_token"))
                XCTAssertTrue(body.contains("refresh_token=r1"))
                return (200, [:], self.json(["access_token": AuthTests.jwt, "expires_in": 300, "token_type": "Bearer"]))
            }
            let auth = request.value(forHTTPHeaderField: "Authorization")
            if auth == "Bearer \(AuthTests.jwt)" {
                return (200, [:], self.json(["items": [], "total": 0, "limit": 50, "offset": 0]))
            }
            return (401, [:], self.json(["error": ["code": "unauthorized", "message": "expired"]]))
        }
        let client = OIDCClientConfig(clientId: "c", redirectURI: "x:/cb", scopes: ["openid"],
                                      authorizationEndpoint: URL(string: "https://idp.test/auth")!,
                                      tokenEndpoint: URL(string: "https://idp.test/token")!, endSessionEndpoint: nil)
        let stale = OIDCTokens(accessToken: "stale-but-not-expired", idToken: nil, refreshToken: "r1", accessTokenExpiresAt: Date().addingTimeInterval(3600))
        let changed = expectation(description: "credential persisted")
        let provider = CredentialProvider(credential: .oidc(stale, client), urlSession: session) { credential in
            if case .oidc(let tokens, _) = credential {
                XCTAssertEqual(tokens.accessToken, AuthTests.jwt)
                XCTAssertEqual(tokens.refreshToken, "r1", "refresh token kept when the IdP doesn't rotate it")
                changed.fulfill()
            }
        }
        let api = APIClient(baseURL: URL(string: "https://m.test")!, credentials: provider, urlSession: session)

        let page = try await api.albums()
        XCTAssertEqual(page.total, 0)
        await fulfillment(of: [changed], timeout: 1)
        XCTAssertEqual(StubURLProtocol.requests.map { $0.url!.host! }, ["m.test", "idp.test", "m.test"])
    }

    func testUnavailableIsNotAnAuthFailure() async {
        StubURLProtocol.handler = { _ in (503, [:], self.json(["error": ["code": "unavailable", "message": "IdP down"]])) }
        let api = APIClient(baseURL: URL(string: "https://m.test")!, credentials: CredentialProvider(credential: .apiToken("t")), urlSession: session) {
            XCTFail("must not sign out on 503")
        }
        do {
            _ = try await api.me()
            XCTFail("expected an error")
        } catch {
            guard case APIError.unavailable = error else { return XCTFail("got \(error)") }
            XCTAssertFalse(APIError.requiresReauthentication(error))
        }
    }
}
