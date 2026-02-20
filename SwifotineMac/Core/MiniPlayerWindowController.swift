import AppKit
import SwiftUI

@MainActor
final class MiniPlayerWindowController: NSObject, NSWindowDelegate {
    static let shared = MiniPlayerWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func show(playbackEngine: PlaybackEngine) {
        if window == nil {
            let rootView = AnyView(
                MiniPlayerView()
                    .environmentObject(playbackEngine)
            )
            let hostingController = NSHostingController(rootView: rootView)

            let createdWindow = NSWindow(contentViewController: hostingController)
            createdWindow.title = "Mini Player"
            createdWindow.styleMask = [.titled, .closable, .miniaturizable]
            createdWindow.setContentSize(NSSize(width: 420, height: 220))
            createdWindow.minSize = NSSize(width: 360, height: 210)
            createdWindow.isReleasedWhenClosed = false
            createdWindow.level = .floating
            createdWindow.delegate = self
            createdWindow.center()

            window = createdWindow
        } else if let hostingController = window?.contentViewController as? NSHostingController<AnyView> {
            hostingController.rootView = AnyView(
                MiniPlayerView()
                    .environmentObject(playbackEngine)
            )
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window?.orderOut(nil)
    }

    func toggle(playbackEngine: PlaybackEngine) {
        if window?.isVisible == true {
            hide()
        } else {
            show(playbackEngine: playbackEngine)
        }
    }

    func windowWillClose(_ notification: Notification) {
        window?.orderOut(nil)
    }
}
