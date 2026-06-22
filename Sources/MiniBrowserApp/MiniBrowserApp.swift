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
            SmokeView()
                .frame(width: 390, height: 844)   // G3: phone width
        }
        .windowResizability(.contentSize)
    }
}

struct SmokeView: View {
    @State private var typed = ""
    var body: some View {
        VStack(spacing: 0) {
            TextField("Type here to verify keyboard focus (G1)", text: $typed)
                .textFieldStyle(.roundedBorder)
                .padding(8)
            SmokeWebView(urlString: "https://www.google.com")
        }
    }
}
