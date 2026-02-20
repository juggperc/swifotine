import AppKit
import SwiftData
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        Task {
            await BackendClient.shared.shutdown()
        }
    }
}

@main
struct SwifotineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var sessionStore = SessionStore()

    // Setup our model container for Tracks, Playlists
    let modelContainer: ModelContainer

    init() {
        modelContainer = Self.makeModelContainer()
    }

    var body: some Scene {
        WindowGroup {
            AppLaunchView()
                .environmentObject(sessionStore)
                .modelContainer(modelContainer)
                .onAppear {
                    Task {
                        // Bootstrap the internal backend
                        await BackendClient.shared.launchHelper()
                    }
                }
        }
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            appCommands()
        }
    }

    @CommandsBuilder
    func appCommands() -> some Commands {
        CommandGroup(replacing: .newItem) {}
        PlaybackCommands()
        SupportCommands()
    }
}

struct PlaybackCommands: Commands {
    @ObservedObject private var playbackEngine = PlaybackEngine.shared

    var body: some Commands {
        CommandMenu("Playback") {
            Button(playbackEngine.state == .playing ? "Pause" : "Play") {
                playbackEngine.togglePlayPause()
            }
            .keyboardShortcut("p", modifiers: [.command])
            .disabled(playbackEngine.currentTrack == nil)

            Button("Stop") {
                playbackEngine.stop()
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(playbackEngine.currentTrack == nil)

            Divider()

            Button("Back 10 Seconds") {
                playbackEngine.seek(by: -10)
            }
            .keyboardShortcut("[", modifiers: [.command])
            .disabled(playbackEngine.currentTrack == nil)

            Button("Forward 10 Seconds") {
                playbackEngine.seek(by: 10)
            }
            .keyboardShortcut("]", modifiers: [.command])
            .disabled(playbackEngine.currentTrack == nil)

            Button("Next in Queue") {
                playbackEngine.skipToNextInQueue()
            }
            .keyboardShortcut("]", modifiers: [.command, .option])
            .disabled(playbackEngine.upNext.isEmpty)

            Divider()

            Button("Show Mini Player") {
                playbackEngine.showMiniPlayer()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        }
    }
}

struct SupportCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .help) {
            Button("Acknowledgements") {
                AcknowledgementsWindowController.shared.show()
            }
            .keyboardShortcut("a", modifiers: [.command, .option])
        }
    }
}

private extension SwifotineApp {
    static func makeModelContainer() -> ModelContainer {
        let fileManager = FileManager.default
        let appSupportRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Swifotine", isDirectory: true)

        if let appSupportRoot {
            try? fileManager.createDirectory(at: appSupportRoot, withIntermediateDirectories: true)
            let storeURL = appSupportRoot.appendingPathComponent("Swifotine.store")
            let configuration = ModelConfiguration(url: storeURL)

            if let container = try? ModelContainer(
                for: Track.self,
                Playlist.self,
                PlaylistEntry.self,
                configurations: configuration
            ) {
                return container
            }

            // Recover from schema/store corruption by clearing the persisted sqlite files.
            try? fileManager.removeItem(at: storeURL)
            try? fileManager.removeItem(atPath: storeURL.path + "-shm")
            try? fileManager.removeItem(atPath: storeURL.path + "-wal")

            if let recoveredContainer = try? ModelContainer(
                for: Track.self,
                Playlist.self,
                PlaylistEntry.self,
                configurations: configuration
            ) {
                return recoveredContainer
            }
        }

        let inMemoryConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
        if let inMemoryContainer = try? ModelContainer(
            for: Track.self,
            Playlist.self,
            PlaylistEntry.self,
            configurations: inMemoryConfiguration
        ) {
            return inMemoryContainer
        }

        preconditionFailure("Unable to initialize SwiftData ModelContainer.")
    }
}
