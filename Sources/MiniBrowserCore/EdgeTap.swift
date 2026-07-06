import Foundation

/// Decides what a mouse release inside the back/forward edge strip means.
///
/// The strip must never let a swipe activate a link, but a press that stayed
/// (almost) still is a deliberate tap on page content — sites routinely put
/// tappable controls in the strip (menu buttons, icons at the left margin) —
/// and swallowing those makes them mysteriously dead.
public enum EdgeTap {
    /// True when the release should be forwarded to the page as a click:
    /// the gesture never became a swipe and total movement stayed within `slop`.
    /// Anything that moved further is a failed swipe attempt and is swallowed.
    public static func shouldForwardClick(becameSwipe: Bool,
                                          movement: Double,
                                          slop: Double = 6) -> Bool {
        !becameSwipe && movement <= slop
    }
}
