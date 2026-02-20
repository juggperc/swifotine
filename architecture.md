# Swifotine Architecture Notes

## Overview

Swifotine is a native macOS AppKit/SwiftUI split application layered over nicotine-plus's core components using an out-of-process helper model.

## Product/Tech Decisions

- **Distribution Model:** Nicotine+ directly with GPL-compatible distribution model.
- **Architecture:** Separate Python helper process (JSON-RPC) instead of in-process Python embedding.
- **Scope is MVP Plus:** login, search, download management, playback, playlists, likes, auto-sort, album art.
- **Playback:** Local/downloaded-files only. Avoid remote streaming in v1.
- **Artwork Policy:** Embedded tags first, then Cover Art Archive, then iTunes fallback.
- **UI:** Music.app-inspired, minimal Vercel-like visual language.
- **Sidebar Sections:** Home, Search, Downloads, Library, Playlists, Liked.
- **Auto-sort:** Default is metadata+folder smart organization.

## Native App Architecture

- **AppShell:** SwiftUI with AppKit bridges for advanced table behavior and command routing.
- **BackendClient:** Actor manages helper lifecycle, request/response correlation, reconnect, and event stream.
- **SessionStore:** @MainActor observable state for auth and connection.
- **SearchStore:** Manages active query tabs, result dedupe, sort/filter.
- **DownloadsStore:** Tracks transfer rows and actions.
- **LibraryStore:** Persists tracks/playlists/likes/artwork metadata via SwiftData.
- **PlaybackEngine:** Wraps AVQueuePlayer.
- **ArtworkPipeline:** Resolves embedded image, remote fetch fallback, and cache.
- **AutoOrganizer:** Handles post-download metadata normalization and file moves.
- **CommandRegistry:** Maps menu/shortcuts to actions.

## Data Model and Persistence

- **SwiftData:** Track, Playlist, PlaylistEntry, Like, ArtworkCache, ImportEvent.
- **Credentials:** macOS Keychain.
- **AppStorage:** User preferences for UI layout and minor settings.
- **Library Root:** ~/Music/Swifotine/Downloads, ~/Music/Swifotine/Library, ~/Music/Swifotine/Incomplete.

## Edge Cases and Failure Handling

- Invalid username/password shows inline corrective UI and keeps user in login state.
- Server disconnect switches to offline state and pauses new actions without data loss.
- Duplicate downloads detected by size+hash+path heuristic; avoid duplicate library entries.
- Partial/failed files stay in downloads with retry affordance.
- Missing metadata falls back to filename parsing and placeholder art.
- Unsupported formats remain downloadable, playable marked unavailable.
