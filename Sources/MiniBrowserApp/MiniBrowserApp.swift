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
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            BrowserView()
                .frame(width: 390, height: 844)
        }
        .windowResizability(.contentSize)
    }
}
