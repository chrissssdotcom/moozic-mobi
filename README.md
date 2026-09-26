# Moozic for iOS

A native SwiftUI client for [Moozic](https://github.com/chrissssdotcom/moozic), the self-hosted music server. It signs in with your identity provider (OAuth 2.0 / OpenID Connect, Authorization Code + PKCE) or with a personal API token (`mzk_…`), and streams from your library with background playback and lock-screen controls.

- **Sign-in:** discovers the server's setup from `GET /api/v1/auth/config`, then either
  - opens the IdP in the system browser (`ASWebAuthenticationSession`, RFC 8252) and refreshes tokens automatically, or
  - takes a personal API token pasted from *Settings → API access* in the web app, or
  - connects straight away when the server runs with `AUTH_MODE=disabled`.
- **Library:** home shelves (jump back in, recently added, discover), albums (sortable, filterable grid), artists, songs, genres, favorites, recently played, and search across all three.
- **Player:** queue with play next / add to queue / reorder / remove, shuffle, repeat, seeking (HTTP Range), background audio, Control Center and lock-screen controls with artwork, plays recorded after 30 s like the web player, optional transcoding (MP3/AAC) to save data.
- **Playlists:** yours and other users' public ones; create, rename, make public, add songs from any list (long-press), remove, and drag to reorder.
- **Settings:** account info, streaming quality, personal API tokens (create/copy/revoke), sign out.

Requires iOS 17 and Xcode 16. No third-party dependencies.

## Building

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen), so it never has merge conflicts:

```bash
brew install xcodegen
xcodegen generate
open Moozic.xcodeproj
```

Pick your team under *Signing & Capabilities* (or set `DEVELOPMENT_TEAM` in `project.yml`) and run. If you change the bundle identifier, change the redirect URI scheme to match (see below).

Tests (PKCE, token refresh and retry, error handling, JSON models) run with ⌘U or:

```bash
xcodebuild test -project Moozic.xcodeproj -scheme Moozic -destination 'platform=iOS Simulator,name=iPhone 16'
```

CI (`.github/workflows/ios.yml`) does the same on every push.

## Releases

Push a version tag and CI builds a Release `.ipa` and publishes it as a GitHub Release (after the tests pass):

```bash
git tag v1.0.0 && git push origin v1.0.0
```

Or run the **iOS** workflow manually from the Actions tab with a version such as `v1.0.1`. It tags the commit it built.

The version comes from the tag and the build number from the CI run. The `.ipa` is **unsigned**, because iOS only installs signed apps. To put it on a phone, sideload it with [AltStore](https://altstore.io), [SideStore](https://sidestore.io) or [Sideloadly](https://sideloadly.io), which re-sign it with your Apple ID. Builds signed with a free Apple ID expire after 7 days. Shipping signed builds (ad-hoc or TestFlight) needs a paid Apple Developer account and its signing credentials stored as repository secrets.

### AltStore source

Each release also updates an [AltStore](https://altstore.io) source that lists every version, so AltStore or SideStore can install the app and notify you of updates. In AltStore, go to **Sources → +** and add:

```
https://github.com/chrissssdotcom/moozic-mobi/releases/latest/download/source.json
```

AltStore downloads the source and the `.ipa` without signing in, so this only works while the repository is public. `scripts/altstore_source.py` builds the source from the GitHub Releases.

## Setting up sign-in (OIDC)

The server docs cover this in [Building a mobile app](https://github.com/chrissssdotcom/moozic/blob/main/docs/api/mobile-clients.md). In short:

1. **Register a public client** at your IdP (no client secret) with:
   - redirect URI `com.chrissss.moozic:/oauth2redirect` (the app's default; editable under *Advanced* on the connect screen),
   - Authorization Code flow with PKCE (`S256`),
   - scopes `openid profile email`, plus `offline_access` if your IdP needs it for refresh tokens (the app asks for it by default).
2. **Tell Moozic to accept it:** add the client ID to `OIDC_ALLOWED_AUDIENCES` on the server.
3. **Make sure the IdP issues JWTs** with that client as `aud`/`azp` (Keycloak does out of the box; Auth0 needs an API audience; Entra ID needs an API scope). If your IdP only issues opaque access tokens, the app automatically sends the ID token instead, which Moozic also accepts.

On the connect screen, enter the server address; the app reads the IdP endpoints and client IDs from the server, pre-selects one that looks like a mobile client (`…mobile…`, `…ios…`), and opens the sign-in page.

If you'd rather not register a client, choose **Use a personal API token instead**.

### How tokens are handled

- Everything is kept in the Keychain (`AfterFirstUnlockThisDeviceOnly`, so background playback works while the phone is locked).
- API calls use the OIDC token and refresh it shortly before it expires. On a `401` the app refreshes and retries once, as the server docs recommend. A `503 unavailable` (the server can't reach the IdP) is shown as a temporary error and never signs you out.
- Audio streams need a credential that outlives a single access token (a long queue can play for hours), so after an OIDC sign-in the app creates a personal API token named "Moozic iOS – <device>" and uses it only for streams. Signing out revokes it. You can see it in *Settings → API Tokens*, labeled "this device".
- Signing out clears the Keychain. It does not end your IdP browser session.

## Local servers over HTTP

App Transport Security allows plain HTTP only for local-network hosts (`NSAllowsLocalNetworking`: `.local` names, bare hostnames and IP addresses). Put anything reachable from the internet behind HTTPS, which you need for OIDC anyway.

## Layout

```
Moozic/
  App/        entry point, SessionStore (account, API client, favorites), RootView and tabs
  Auth/       PKCE, OIDC sign-in and token refresh, Keychain storage, auth models
  API/        APIClient (auth, retry, errors), typed endpoints, models, cover image loader
  Player/     PlayerController (AVPlayer queue, Now Playing, remote commands), stream quality
  Views/      Connect, Library, Playlists, Player, Settings, shared components
MoozicTests/  unit tests
project.yml   XcodeGen spec
```

## Known limitations

- Ogg/Opus originals won't play, because AVPlayer can't decode them. Pick an MP3/AAC streaming quality in Settings to have the server transcode them (needs ffmpeg on the server).
- Transcoded streams can't be scrubbed. This is a server-side limitation.
- There's no offline downloading yet, and no admin screens (metadata fixer, Soulseek). Those stay in the web app.
