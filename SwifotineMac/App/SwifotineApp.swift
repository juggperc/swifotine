import SwiftUI
import AppKit

@main
struct SwifotineApp: App {
    @StateObject private var sessionStore = SessionStore()
    
    var body: some Scene {
        WindowGroup {
            AppShell()
                .environmentObject(sessionStore)
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
        CommandGroup(replacing: .newItem) { }
    }
}
