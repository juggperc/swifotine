import SwiftData
import SwiftUI

@main
struct SwifotineApp: App {
    @StateObject private var sessionStore = SessionStore()

    // Setup our model container for Tracks, Playlists
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: Track.self, Playlist.self, PlaylistEntry.self)
        } catch {
            fatalError("Failed to configure SwiftData container.")
        }
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
