#!/usr/bin/env python3
"""Build an AltStore source (https://faq.altstore.io/developers/make-a-source) from GitHub Releases.

Usage: altstore_source.py RELEASES_JSON OWNER/REPO > source.json

RELEASES_JSON is the output of `gh api repos/OWNER/REPO/releases`. Every published,
non-draft release with a `*.ipa` asset becomes a version, newest first.
"""
import json
import sys

BUNDLE_ID = "com.chrissss.moozic"
MIN_OS = "17.0"
TINT = "7C5CF6"


def build(releases, repo):
    raw = f"https://raw.githubusercontent.com/{repo}/main"
    icon = f"{raw}/Moozic/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    versions = []
    for release in releases:
        if release.get("draft") or release.get("prerelease"):
            continue
        ipa = next((a for a in release.get("assets", []) if a["name"].endswith(".ipa")), None)
        if not ipa:
            continue
        versions.append({
            "version": release["tag_name"].lstrip("v"),
            "date": release.get("published_at") or release["created_at"],
            "localizedDescription": (release.get("body") or release.get("name") or "").strip(),
            "downloadURL": ipa["browser_download_url"],
            "size": ipa["size"],
            "minOSVersion": MIN_OS,
        })
    versions.sort(key=lambda v: v["date"], reverse=True)

    return {
        "name": "Moozic",
        "identifier": f"{BUNDLE_ID}.source",
        "subtitle": "Builds of the Moozic iOS app.",
        "description": "Native iOS client for Moozic, the self-hosted music server.",
        "iconURL": icon,
        "website": f"https://github.com/{repo}",
        "tintColor": TINT,
        "apps": [{
            "name": "Moozic",
            "bundleIdentifier": BUNDLE_ID,
            "developerName": repo.split("/")[0],
            "subtitle": "Your self-hosted music, anywhere.",
            "localizedDescription": (
                "Stream your Moozic library: albums, artists, playlists, favorites and search, "
                "with background playback and lock-screen controls. Sign in with your identity "
                "provider (OIDC) or a personal API token."
            ),
            "iconURL": icon,
            "tintColor": TINT,
            "category": "entertainment",
            "screenshots": [],
            "versions": versions,
            "appPermissions": {
                "entitlements": [],
                "privacy": {
                    "NSLocalNetworkUsageDescription": "Moozic connects to your music server on the local network.",
                },
            },
        }],
        "news": [],
    }


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[1]) as f:
        releases = json.load(f)
    json.dump(build(releases, sys.argv[2]), sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
