import SwiftUI
import AppKit

@main
struct MiniBrowserApp: App {
    init() {
        // G1: swift-run binaries start non-.regular (no bundle). Without this:
        // no Dock icon, window behind others, NO keyboard focus, Cmd-Q kills the shell.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            // G1: the window may not exist yet on first launch. Guard + bounded retry
            // on the next main-runloop turn (no infinite loop).
            Self.bringWindowToFront(attemptsRemaining: 10)
        }
    }

    /// Brings the first window to the front, retrying on subsequent main-runloop turns
    /// until a window exists or the bounded attempt budget is exhausted.
    @MainActor
    private static func bringWindowToFront(attemptsRemaining: Int) {
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard attemptsRemaining > 0 else { return }
        DispatchQueue.main.async {
            bringWindowToFront(attemptsRemaining: attemptsRemaining - 1)
        }
    }

    var body: some Scene {
        WindowGroup {
            BrowserView()
                .frame(idealWidth: 390, maxWidth: .infinity,
                       idealHeight: 844, maxHeight: .infinity)
                .preferredColorScheme(.dark)   // default to dark theme
        }
        // No .contentMinSize resizability: BossMode sets a small window.minSize
        // directly so it can shrink the window below the content's natural min.
        .windowResizability(.automatic)
    }
}
