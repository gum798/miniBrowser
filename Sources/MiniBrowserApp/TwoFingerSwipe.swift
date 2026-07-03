// Sources/MiniBrowserApp/TwoFingerSwipe.swift
import AppKit
import WebKit

/// Trackpad two-finger horizontal swipe = back/forward over the tab's page stack,
/// Safari-style. WebKit's own gesture only works within a single web view's
/// history; this covers the stacked (instant) pages. When the current web view can
/// navigate natively in the swipe direction, events are left alone so the native
/// interactive gesture keeps working. Installed once; lives for the app's lifetime.
@MainActor
final class TwoFingerSwipe {
    private var monitor: Any?
    private var accumX: CGFloat = 0
    private var accumY: CGFloat = 0
    private var goingBack = true
    private var peek: WKWebView?   // live page shown under the current one while swiping
    private var mode: Mode = .idle
    private let threshold: CGFloat = 80   // accumulated horizontal points to commit

    private enum Mode { case idle, navigating, passthrough, swallowingMomentum }

    private let tabProvider: () -> Tab?

    init(tabProvider: @escaping () -> Tab?) {
        self.tabProvider = tabProvider
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // The local monitor's closure is non-Sendable, so it inherits this
            // @MainActor-isolated context; call the isolated handler directly.
            // (Mirrors installZoomKeys(); MainActor.assumeIsolated is rejected here
            // because its result type NSEvent? is not Sendable under Swift 6.)
            self?.handle(event) ?? event
        }
    }

    /// Returns nil to consume the event (we're driving a navigation swipe).
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let tab = tabProvider(), let window = tab.webView.window,
              event.window === window else { return event }
        let webView = tab.webView

        if event.momentumPhase != [] {
            // Inertia after a swipe we consumed: keep swallowing so the page
            // doesn't scroll once the navigation has been decided.
            return mode == .swallowingMomentum ? nil : event
        }

        switch event.phase {
        case .began:
            accumX = 0; accumY = 0; mode = .idle
            return event
        case .changed:
            guard mode != .passthrough else { return event }
            accumX += event.scrollingDeltaX
            accumY += event.scrollingDeltaY
            if mode == .idle {
                if abs(accumY) > 12, abs(accumY) > abs(accumX) {
                    mode = .passthrough                        // clearly a scroll
                } else if abs(accumX) > 12, abs(accumX) > 2 * abs(accumY) {
                    goingBack = accumX > 0                      // fingers right = back
                    let nativeHandles = goingBack ? webView.canGoBack : webView.canGoForward
                    let stackHas = goingBack ? tab.canGoBack : tab.canGoForward
                    // Leave native in-page history to WebKit's own gesture.
                    mode = (!nativeHandles && stackHas) ? .navigating : .passthrough
                }
            }
            guard mode == .navigating else { return event }
            installPeekIfNeeded(tab: tab, under: webView)
            setOffset(offset(), on: webView)
            return nil
        case .ended, .cancelled:
            guard mode == .navigating else { mode = .idle; return event }
            let commit = (goingBack ? accumX : -accumX) >= threshold
            // Leave the page translated when a live peek will be swapped in — the
            // revealed page is already fully visible beneath; resetting first would
            // flash the old page back over it for a frame.
            if peek == nil || !commit { setOffset(0, on: webView) }
            if commit {
                if goingBack { tab.goBack() } else { tab.goForward() }
                peek = nil                                     // swap re-attaches subviews
            } else {
                removePeek(afterDelay: 0.25)                   // visible under the snap-back
            }
            mode = .swallowingMomentum
            return nil
        default:
            return event
        }
    }

    /// Follow the fingers a little (capped) in the navigation direction only.
    private func offset() -> CGFloat {
        goingBack ? min(160, max(0, accumX)) : max(-160, min(0, accumX))
    }

    private func setOffset(_ dx: CGFloat, on webView: WKWebView) {
        webView.layer?.setAffineTransform(CGAffineTransform(translationX: dx, y: 0))
    }

    /// Put the live page the gesture would reveal UNDER the current web view
    /// (book-flip effect, same as the edge drag).
    private func installPeekIfNeeded(tab: Tab, under webView: WKWebView) {
        guard peek == nil, let container = webView.superview,
              let target = tab.peekView(back: goingBack) else { return }
        target.frame = container.bounds
        target.autoresizingMask = [.width, .height]
        target.layer?.setAffineTransform(.identity)   // clear any stale swipe transform
        container.addSubview(target, positioned: .below, relativeTo: webView)
        peek = target
    }

    private func removePeek(afterDelay delay: TimeInterval) {
        guard let peek else { return }
        self.peek = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { peek.removeFromSuperview() }
    }
}
