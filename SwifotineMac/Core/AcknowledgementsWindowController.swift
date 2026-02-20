import AppKit
import SwiftUI

@MainActor
final class AcknowledgementsWindowController: NSObject, NSWindowDelegate {
    static let shared = AcknowledgementsWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func show() {
        if window == nil {
            let rootView = AnyView(AcknowledgementsView())
            let hostingController = NSHostingController(rootView: rootView)

            let createdWindow = NSWindow(contentViewController: hostingController)
            createdWindow.title = "Acknowledgements"
            createdWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            createdWindow.setContentSize(NSSize(width: 560, height: 420))
            createdWindow.minSize = NSSize(width: 480, height: 360)
            createdWindow.isReleasedWhenClosed = false
            createdWindow.delegate = self
            createdWindow.center()

            window = createdWindow
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window?.orderOut(nil)
    }
}
