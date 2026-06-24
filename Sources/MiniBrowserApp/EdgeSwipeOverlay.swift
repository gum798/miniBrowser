import AppKit
import WebKit

/// Transparent overlay over the web view that turns a horizontal mouse drag from
/// the left/right edge into back/forward navigation, iOS-style: the page follows
/// the drag and a chevron hints the direction; releasing past the threshold
/// navigates, otherwise it snaps back.
///
/// It only intercepts the left/right edge zones (a third of the width each, ≥100pt)
/// and only when navigation that way is possible, so the middle and dead edges work
/// normally. Inside an active edge zone a quick tap is swallowed — so a swipe never
/// activates a link/image — while a long press passes the click through to the page.
@MainActor
final class EdgeSwipeOverlay: NSView {
    weak var tab: Tab?

    private var downPoint: NSPoint = .zero
    private var downTime: TimeInterval = 0
    private var fromLeft = true
    private var swiping = false
    private var offset: CGFloat = 0

    private let longPress: TimeInterval = 0.35
    private func edge() -> CGFloat { max(40, bounds.width * 0.10) }   // narrow back/forward strip
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
        downTime = event.timestamp
        fromLeft = downPoint.x <= edge()
        swiping = false
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let dx = p.x - downPoint.x, dy = p.y - downPoint.y
        if !swiping, abs(dx) > 8, abs(dx) > abs(dy),
           (fromLeft && dx > 0) || (!fromLeft && dx < 0) {
            swiping = true
        }
        if swiping { setOffset(fromLeft ? max(0, dx) : min(0, dx)) }
    }

    override func mouseUp(with event: NSEvent) {
        let dx = convert(event.locationInWindow, from: nil).x - downPoint.x
        if swiping {
            if (fromLeft ? dx : -dx) >= threshold() {
                if fromLeft { tab?.goBack() } else { tab?.goForward() }
                setOffset(0)                 // new page renders in place
            } else {
                setOffset(0, animated: true) // snap back
            }
        } else if event.timestamp - downTime >= longPress {
            forwardClick(at: downPoint)       // long press -> real click
        }                                     // quick tap -> swallowed
        swiping = false
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

    /// Click the element under a long press by hit-testing the page (overlay coords
    /// are top-left and ≈ CSS pixels for the mobile-width viewport).
    private func forwardClick(at p: NSPoint) {
        tab?.webView.evaluateJavaScript(
            "var e=document.elementFromPoint(\(Int(p.x)),\(Int(p.y)));if(e){e.click();}")
    }
}
