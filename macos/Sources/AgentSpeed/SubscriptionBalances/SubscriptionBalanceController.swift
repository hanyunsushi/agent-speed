import AppKit
import SwiftUI

/// Owns the balance controls; the shared speed status item draws the balance text.
@MainActor
final class SubscriptionBalanceController: NSObject {
    private let state: SubscriptionBalanceState
    private var settingsWindow: NSWindow?

    init(state: SubscriptionBalanceState) {
        self.state = state
        super.init()
    }

    /// Settings must remain reachable when macOS has pushed the status item offscreen.
    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 660),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Sub 4 Tokens"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView:
                ScrollView { SubscriptionBalancePopover(state: state).frame(width: 360) }
                    .frame(width: 360, height: 660))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func stop() {
        settingsWindow?.close()
        state.stop()
    }
}
