import XCTest
@testable import Moozic

final class AuthTests: XCTestCase {
    // exp = 2000000000 (2033), aud = moozic-mobile
    static let jwt = "eyJhbGciOiJSUzI1NiJ9.eyJpc3MiOiJodHRwczovL2lkcCIsImV4cCI6MjAwMDAwMDAwMCwiYXVkIjoibW9vemljLW1vYmlsZSJ9.sig"

    func testPKCEChallengeIsBase64URLSHA256OfVerifier() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mJ92heXZh9Ok5mD-4M-S1hq4-4oEcwVgk")
        XCTAssertEqual(pkce.challenge, "Mfn_dufP6NOur5xkqhshD8xhyZCSeMWZPp-xu_ddDyM")
        XCTAssertEqual(pkce.method, "S256")
    }

    func testGeneratedVerifierIsURLSafeAndLongEnough() {
        let verifier = PKCE().verifier
        XCTAssertGreaterThanOrEqual(verifier.count, 43)
        XCTAssertNil(verifier.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
        XCTAssertNotEqual(PKCE().verifier, PKCE().verifier)
    }

    func testJWTInspection() {
        XCTAssertTrue(JWT.isJWT(Self.jwt))
        XCTAssertFalse(JWT.isJWT("opaque-access-token"))
        XCTAssertFalse(JWT.isJWT("mzk_abc.def.ghi"))
        XCTAssertEqual(JWT.expiry(of: Self.jwt), Date(timeIntervalSince1970: 2_000_000_000))
    }

    func testBearerPrefersJWTAccessTokenAndFallsBackToIDToken() {
        let jwtAccess = OIDCTokens(accessToken: Self.jwt, idToken: "other", refreshToken: nil, accessTokenExpiresAt: nil)
        XCTAssertEqual(jwtAccess.bearer, Self.jwt)

        let opaqueAccess = OIDCTokens(accessToken: "opaque", idToken: Self.jwt, refreshToken: nil, accessTokenExpiresAt: nil)
        XCTAssertEqual(opaqueAccess.bearer, Self.jwt)
        XCTAssertEqual(opaqueAccess.bearerExpiresAt, Date(timeIntervalSince1970: 2_000_000_000))
    }

    func testNeedsRefresh() {
        let soon = OIDCTokens(accessToken: "opaque", idToken: nil, refreshToken: "r", accessTokenExpiresAt: Date().addingTimeInterval(30))
        XCTAssertTrue(soon.needsRefresh())
        let later = OIDCTokens(accessToken: "opaque", idToken: nil, refreshToken: "r", accessTokenExpiresAt: Date().addingTimeInterval(600))
        XCTAssertFalse(later.needsRefresh())
    }

    func testMergeKeepsTokensTheIdPDidNotRotate() {
        let old = OIDCTokens(accessToken: "a1", idToken: "i1", refreshToken: "r1", accessTokenExpiresAt: nil)
        let fresh = OIDCTokens(accessToken: "a2", idToken: nil, refreshToken: nil, accessTokenExpiresAt: nil)
        let merged = old.merged(with: fresh)
        XCTAssertEqual(merged.accessToken, "a2")
        XCTAssertEqual(merged.idToken, "i1")
        XCTAssertEqual(merged.refreshToken, "r1")
    }

    func testSuggestedClientId() {
        func config(_ ids: [String]) -> AuthConfig {
            AuthConfig(mode: "oidc", issuer: nil, discoveryUrl: nil, authorizationEndpoint: nil, tokenEndpoint: nil,
                       endSessionEndpoint: nil, clientIds: ids, scopes: nil, pkce: nil, apiTokens: nil)
        }
        XCTAssertEqual(config(["moozic-web", "moozic-mobile"]).suggestedClientId, "moozic-mobile")
        XCTAssertEqual(config(["web", "ios-client", "x"]).suggestedClientId, "ios-client")
        XCTAssertEqual(config(["moozic"]).suggestedClientId, "moozic")
        XCTAssertNil(config([]).suggestedClientId)
    }

    func testAuthorizationURL() throws {
        let client = OIDCClientConfig(
            clientId: "moozic-mobile",
            redirectURI: OIDCClientConfig.defaultRedirectURI,
            scopes: ["openid", "profile", "offline_access"],
            authorizationEndpoint: URL(string: "https://idp.example.com/auth?kc_idp_hint=x")!,
            tokenEndpoint: URL(string: "https://idp.example.com/token")!,
            endSessionEndpoint: nil
        )
        XCTAssertEqual(client.callbackScheme, "com.chrissss.moozic")
        let pkce = PKCE(verifier: "v".padding(toLength: 43, withPad: "v", startingAt: 0))
        let url = try OIDCAuthenticator.authorizationURL(client: client, pkce: pkce, state: "s1", nonce: "n1")
        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["kc_idp_hint"], "x")
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["client_id"], "moozic-mobile")
        XCTAssertEqual(items["redirect_uri"], "com.chrissss.moozic:/oauth2redirect")
        XCTAssertEqual(items["scope"], "openid profile offline_access")
        XCTAssertEqual(items["state"], "s1")
        XCTAssertEqual(items["code_challenge"], pkce.challenge)
        XCTAssertEqual(items["code_challenge_method"], "S256")
    }

    func testAuthorizationCodeParsing() throws {
        let ok = URL(string: "com.chrissss.moozic:/oauth2redirect?code=abc&state=s1")!
        XCTAssertEqual(try OIDCAuthenticator.authorizationCode(from: ok, expectedState: "s1"), "abc")

        XCTAssertThrowsError(try OIDCAuthenticator.authorizationCode(from: ok, expectedState: "other")) {
            XCTAssertEqual($0 as? OIDCError, .stateMismatch)
        }
        let denied = URL(string: "com.chrissss.moozic:/oauth2redirect?error=access_denied&error_description=Nope&state=s1")!
        XCTAssertThrowsError(try OIDCAuthenticator.authorizationCode(from: denied, expectedState: "s1")) {
            XCTAssertEqual($0 as? OIDCError, .authorizationFailed("Nope"))
        }
    }

    func testFormBodyEncoding() {
        let body = String(data: TokenClient.formBody(["redirect_uri": "com.x:/cb?a=1&b", "code": "a+b c"]), encoding: .utf8)
        XCTAssertEqual(body, "code=a%2Bb%20c&redirect_uri=com.x%3A%2Fcb%3Fa%3D1%26b")
    }

    func testCredentialRoundTripsThroughCodable() throws {
        let client = OIDCClientConfig(clientId: "c", redirectURI: "r:/x", scopes: ["openid"],
                                      authorizationEndpoint: URL(string: "https://a")!, tokenEndpoint: URL(string: "https://t")!, endSessionEndpoint: nil)
        let accounts = [
            Account(serverURL: URL(string: "https://m")!, credential: .anonymous),
            Account(serverURL: URL(string: "https://m")!, credential: .apiToken("mzk_1"), mediaToken: MediaToken(id: nil, token: "mzk_1")),
            Account(serverURL: URL(string: "https://m")!, credential: .oidc(OIDCTokens(accessToken: "a", idToken: nil, refreshToken: "r", accessTokenExpiresAt: Date(timeIntervalSince1970: 100)), client), mediaToken: MediaToken(id: 4, token: "mzk_2")),
        ]
        for account in accounts {
            let decoded = try JSONDecoder().decode(Account.self, from: JSONEncoder().encode(account))
            XCTAssertEqual(decoded, account)
        }
    }
}
