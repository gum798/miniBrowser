import SwiftUI
import AppKit

/// "Boss key": when the mouse hasn't been over the window for a while, shrink it
/// to a small box so it's inconspicuous. Keeping the mouse over it keeps it full
/// size; once shrunk, a click restores it.
///
/// Uses cursor-position polling (no event tap / accessibility permission) so it
/// keeps working while another app is in front — which is the whole point.
@MainActor
final class BossMode: ObservableObject {
    @Published var enabled = true {
        didSet { if !enabled { restore() }; idleSince = Date() }
    }

    private weak var window: NSWindow?
    private var timer: Timer?
    private var idleSince = Date()
    private var shrunk = false
    private var savedFrame: NSRect = .zero

    private let idleLimit: TimeInterval = 10
    private let shrunkSize = NSSize(width: 160, height: 140)

    func attach(_ window: NSWindow) {
        guard self.window == nil else { return }   // wire up once
        self.window = window
        window.minSize = NSSize(width: 120, height: 80)   // allow shrinking below content's natural min
        window.isRestorable = false                       // never persist a (possibly shrunk) frame across launches
        // Recover if a previous run left the window tiny: reopen at the normal size, centered.
        if window.frame.width < 320 || window.frame.height < 320,
           let screen = window.screen ?? NSScreen.main {
            let size = NSSize(width: 390, height: 844)
            let origin = NSPoint(x: screen.visibleFrame.midX - size.width / 2,
                                 y: screen.visibleFrame.midY - size.height / 2)
            window.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        idleSince = Date()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation

        if shrunk {
            let clicking = NSEvent.pressedMouseButtons & 0x1 != 0
            if clicking, window.frame.contains(mouse) { restore() }
            return
        }
        guard enabled else { idleSince = Date(); return }

        if window.frame.contains(mouse) {
            idleSince = Date()
        } else if Date().timeIntervalSince(idleSince) >= idleLimit {
            shrink()
        }
    }

    private func shrink() {
        guard let window, !shrunk else { return }
        shrunk = true
        savedFrame = window.frame
        // anchor the top-left corner where the full window was
        let origin = NSPoint(x: savedFrame.minX, y: savedFrame.maxY - shrunkSize.height)
        window.setFrame(NSRect(origin: origin, size: shrunkSize), display: true, animate: true)
    }

    private func restore() {
        guard let window, shrunk else { return }
        shrunk = false
        window.setFrame(savedFrame, display: true, animate: true)
        idleSince = Date()
    }
}

/// Hands the hosting `NSWindow` to a callback once it exists.
struct WindowReader: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { [weak v] in if let w = v?.window { onWindow(w) } }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        if let w = nsView.window { onWindow(w) }
    }
}
