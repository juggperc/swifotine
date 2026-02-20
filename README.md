# Swifotine

Native macOS Soulseek client prototype built with SwiftUI, SwiftData, and a Python helper that wraps Nicotine+ core services.

## What it does

- Login/connect to Soulseek through an embedded helper process.
- Global search with:
  - tabbed searches
  - persistent search history
  - file metadata/details panel
- Queue and monitor downloads from search results.
- Organize completed files into your local library.
- Package into a standalone `.app` and `.dmg`.

## Repository layout

- `SwifotineMac/` - SwiftUI macOS app.
- `backend/slsk-helper/swifotine_helper.py` - JSON-RPC bridge to Nicotine+.
- `vendor/nicotine-plus/` - vendored Nicotine+ engine.
- `scripts/build_release_dmg.sh` - release app + DMG builder.
- `scripts/generate_app_icon.sh` - icon generation script.
- `assets/` - app icon sources (`AppIcon.icns`, base PNG, iconset).

## Requirements

- macOS 14+
- Xcode command line tools
- Swift 5.9+
- Python 3 (system Python is fine)

## Run from source

```bash
cd SwifotineMac
swift run
```

## Build app + DMG

From repo root:

```bash
./scripts/build_release_dmg.sh 1.0
```

Outputs:

- `dist/Swifotine.app`
- `Swifotine_v1.0.dmg`

## Notes on downloads

- Search downloads are enqueued through the helper RPC method `download.enqueue`.
- The helper now force-initializes share readiness for queue dispatch when needed, which prevents transfers from remaining stuck in a local queued state.
- Download updates carry stable transfer IDs derived from source user + virtual path, improving state tracking.

## Additional docs

- `architecture.md`
- `ipc.md`
- `licensing.md`
