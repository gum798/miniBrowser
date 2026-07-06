import AppKit
import WebKit
import MiniBrowserCore

/// Transparent overlay over the web view that turns a horizontal mouse drag from
/// the left/right edge into back/forward navigation, iOS-style: the page follows
/// the drag and a chevron hints the direction; releasing past the threshold
/// navigates, otherwise it snaps back.
///
/// It only intercepts the left/right edge zones (60pt each) and only when
/// navigation that way is possible, so the middle and dead edges work normally.
/// A press that stays within the tap slop is a deliberate tap on page content
/// (sites put buttons in the strip) — its original mouse events are replayed
/// into the web view, so in-strip controls stay clickable at any zoom. Only a
/// press that moved without becoming a swipe (a failed swipe) is swallowed.
@MainActor
final class EdgeSwipeOverlay: NSView {
    weak var tab: Tab?

    private var downPoint: NSPoint = .zero
    private var downEvent: NSEvent?         // replayed into the web view when the press turns out to be a tap
    private var movement: CGFloat = 0       // max distance from downPoint, any direction
    private var fromLeft = true
    private var swiping = false
    private var offset: CGFloat = 0
    private var peek: WKWebView?   // live page shown under the current one while swiping

    private func edge() -> CGFloat { 60 }   // back/forward swipe strip width (pt)
    private func threshold() -> CGFloat { max(60, bounds.width * 0.22) }

    override var isFlipped: Bool { true }   // top-left origin, matches web/page coords

    /// Claim only the active edge zone; everything else falls through to the web view.
    override func hitTest(_ point: NSPoint) -> NSView? {
        // While picking elements to hide, stay out of the way so every click reaches
        // the page and uses WebKit's native (accurate) hit-testing.
        if ElementHider.shared.picking { return nil }
        guard let sv = superview else { return nil }
        let p = convert(point, from: sv)
        if p.x <= edge(), tab?.canGoBack == true { return self }
        if p.x >= bounds.width - edge(), tab?.canGoForward == true { return self }
        return nil
    }

    /// Keep vertical scrolling alive in the edge zone by forwarding wheel events
    /// to the actual content view under the pointer inside the web view.
    override func scrollWheel(with event: NSEvent) {
        guard let webView = tab?.webView else { return }
        let p = webView.convert(event.locationInWindow, from: nil)
        (webView.hitTest(p) ?? webView).scrollWheel(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        downPoint = convert(event.locationInWindow, from: nil)
        downEvent = event
        movement = 0
        fromLeft = downPoint.x <= edge()
        swiping = false
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let dx = p.x - downPoint.x, dy = p.y - downPoint.y
        movement = max(movement, hypot(dx, dy))
        if !swiping, abs(dx) > 8, abs(dx) > abs(dy),
           (fromLeft && dx > 0) || (!fromLeft && dx < 0) {
            swiping = true
        }
        if swiping {
            installPeekIfNeeded()
            setOffset(fromLeft ? max(0, dx) : min(0, dx))
        }
    }

    override func mouseUp(with event: NSEvent) {
        let dx = convert(event.locationInWindow, from: nil).x - downPoint.x
        if swiping {
            if (fromLeft ? dx : -dx) >= threshold() {
                let old = tab?.webView
                if fromLeft { tab?.goBack() } else { tab?.goForward() }
                if old !== tab?.webView {
                    // Swapped to a stack page. Normalize the container ourselves:
                    // with the peek sitting at subviews.first, updateNSView's
                    // `subviews.first !== webView` check cannot see this swap, so
                    // the old (translated) view would linger on top. Removing both
                    // here makes the queued SwiftUI pass re-attach the new current
                    // view cleanly (constraints + fresh overlay), with no paint in
                    // between.
                    peek?.removeFromSuperview()
                    old?.removeFromSuperview()
                    old?.layer?.setAffineTransform(.identity)   // clean for its life on the stack
                } else {
                    setOffset(0)                 // same view stays (native history) — undo the drag
                    peek?.removeFromSuperview()  // defensive: no peek should exist on this path
                }
                peek = nil
            } else {
                setOffset(0, animated: true) // snap back
                removePeek(afterDelay: 0.25) // keep it visible under the snap-back animation
            }
        } else if EdgeTap.shouldForwardClick(becameSwipe: false, movement: movement) {
            forwardTap(with: event)           // deliberate tap -> real click on the page
        }                                     // moved-but-not-swipe -> swallowed
        swiping = false
        downEvent = nil
    }

    /// Replay the press into the web view so an in-strip tap behaves like a normal
    /// click. Real events keep window coordinates, so WebKit's own hit-testing does
    /// the rest — correct at any page zoom, and focus/:active work as usual.
    private func forwardTap(with up: NSEvent) {
        guard let webView = tab?.webView else { return }
        if let downEvent { webView.mouseDown(with: downEvent) }
        webView.mouseUp(with: up)
    }

    /// Put the live page the gesture would reveal UNDER the current web view, so
    /// dragging the page aside uncovers the real screen (book-flip effect).
    private func installPeekIfNeeded() {
        guard peek == nil, let container = superview, let current = tab?.webView,
              let target = tab?.peekView(back: fromLeft) else { return }
        target.translatesAutoresizingMaskIntoConstraints = true   // frame-based while peeking (attach() re-enables constraints)
        target.frame = container.bounds
        target.autoresizingMask = [.width, .height]
        target.layer?.setAffineTransform(.identity)   // clear any stale swipe transform
        container.addSubview(target, positioned: .below, relativeTo: current)
        peek = target
    }

    private func removePeek(afterDelay delay: TimeInterval) {
        guard let peek else { return }
        self.peek = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard self?.peek !== peek else { return }   // re-installed by a newer swipe — keep it
            peek.removeFromSuperview()
        }
    }

    /// Slide the web view to follow the drag; redraw the chevron hint.
    private func setOffset(_ dx: CGFloat, animated: Bool = false) {
        offset = dx
        guard let layer = tab?.webView.layer else { return }
        let apply = { layer.setAffineTransform(CGAffineTransform(translationX: dx, y: 0)) }
        if animated {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.2; apply() }
        } else {
            apply()
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard peek == nil else { return }
        guard swiping, offset != 0 else { return }
        let reveal = abs(offset)
        let progress = min(1, reveal / threshold())
        let s = NSAttributedString(string: fromLeft ? "‹" : "›", attributes: [
            .font: NSFont.systemFont(ofSize: 34, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(progress),
        ])
        let sz = s.size()
        let cx = fromLeft ? reveal / 2 : bounds.width - reveal / 2
        s.draw(at: NSPoint(x: cx - sz.width / 2, y: bounds.midY - sz.height / 2))
    }
}
