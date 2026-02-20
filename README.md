# Swifotine

Native macOS Soulseek client prototype built with SwiftUI, SwiftData, and a Python helper that wraps Nicotine+ core services.

## What it does

- Login/connect to Soulseek through an embedded helper process.
- Global search with:
  - tabbed searches
  - relevance-ranked results
  - bounded runtime (idle finish + hard timeout + max-results cap)
  - persistent search history with restorable cached results
  - file metadata/details panel
- Queue and monitor downloads from search results.
- Persist download transfer state across app relaunches.
- Organize completed files into your local library (SwiftData persistent store).
- Library supports table and grid layouts with embedded artwork (and procedural fallback covers).
- Playlists support custom procedural covers influenced by user-provided text.
- Playback queue supports "Play Next" and "Add to Queue" from library context menus.
- Native music playback with timeline scrubbing, artwork, and a mini player window.
- Acknowledgements pop-out (Help menu) for bundled/open-source dependencies.
- Short animated splash screen on launch for smoother startup handoff.
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
- Search results now use the actual remote peer username from Nicotine+ responses.
- The helper force-initializes share readiness for queue dispatch when needed, preventing transfers from remaining stuck in a local queued state.
- Download updates carry stable transfer IDs derived from source user + virtual path, improving state tracking.
- Smart source failover: when downloading a selected file, the app can enqueue additional matching peers (same path/size) to improve start reliability when a single source stalls.
- Transfer state is serialized to `~/Library/Application Support/Swifotine/downloads-state.json` and restored at launch.
- Track metadata parsing now uses filename + folder heuristics for better artist/album/title detection.

## Notes on search

- Each search is tokenized and bounded: the app automatically stops a search after inactivity, when the hard time limit is reached, or when ranked results hit the cap.
- Results are ranked by query-text match and transfer quality signals (free slots, queue depth, peer speed, bitrate).
- Search history snapshots are serialized to `~/Library/Application Support/Swifotine/search-history.json` for quick reuse.

## Notes on library and playlists

- Playlist cover profiles are serialized to `~/Library/Application Support/Swifotine/playlist-covers.json`.
- You can switch Library between table and grid modes; grid cards render procedural album covers from track metadata.

## Useful shortcuts

- `⌘P`: Play/Pause
- `⌘.`: Stop playback
- `⌘[` / `⌘]`: Seek back/forward 10 seconds
- `⌘⌥]`: Next in queue
- `⌘⇧M`: Show mini player
- `⌘⌥A`: Show Acknowledgements

## Additional docs

- `architecture.md`
- `ipc.md`
- `licensing.md`
