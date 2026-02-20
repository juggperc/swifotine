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
            AppShell()
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
