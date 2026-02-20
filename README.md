# Swifotine

Native macOS Soulseek client built with SwiftUI/SwiftData and a Python helper around Nicotine+.

## Highlights

- Search with tabs, ranking, and history
- Download queue + transfer persistence
- Library with list/grid layouts and artwork
- Playlists + queue controls
- Native playback, mini player, and keyboard shortcuts

## Project layout

- `SwifotineMac/` macOS app
- `backend/slsk-helper/swifotine_helper.py` helper bridge
- `vendor/nicotine-plus/` vendored engine
- `scripts/build_release_dmg.sh` release packager

## Requirements

- macOS 14+
- Xcode Command Line Tools
- Swift 5.9+
- Python 3

## Run locally

```bash
cd SwifotineMac
swift run
```

## Build `.app` and `.dmg`

```bash
./scripts/build_release_dmg.sh 1.0
```

Output:

- `dist/Swifotine.app`
- `Swifotine_v1.0.dmg`

## Release builds (for other users)

Use Developer ID signing + notarization:

```bash
export SWIFOTINE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export SWIFOTINE_NOTARIZE=1
export SWIFOTINE_NOTARY_PROFILE="AC_NOTARY_PROFILE"
./scripts/build_release_dmg.sh 1.0
```

For local/internal testing only (not distributable):

```bash
export SWIFOTINE_ALLOW_UNTRUSTED_RELEASE=1
./scripts/build_release_dmg.sh 1.0
```

## GitHub Actions

- `/.github/workflows/swift.yml` CI build + test + artifact upload
- `/.github/workflows/release.yml` signed/notarized release on `v*` tags

Required repository secrets:

- `MACOS_CERT_P12_BASE64`
- `MACOS_CERT_PASSWORD`
- `NOTARY_APPLE_ID`
- `NOTARY_TEAM_ID`
- `NOTARY_APP_PASSWORD`

## Data locations

- Downloads state: `~/Library/Application Support/Swifotine/downloads-state.json`
- Search history: `~/Library/Application Support/Swifotine/search-history.json`
- Playlist cover profiles: `~/Library/Application Support/Swifotine/playlist-covers.json`

## Docs

- `architecture.md`
- `ipc.md`
- `licensing.md`
