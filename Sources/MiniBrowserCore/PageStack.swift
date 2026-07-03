// Sources/MiniBrowserCore/PageStack.swift
import Foundation

/// Back/forward stacks of pages kept *alive* so navigating them is instant, with
/// a cap on how many live pages each stack may hold. When the cap is exceeded,
/// elements farthest from the current page (the stack bottom) are demoted via
/// `demote` — the app turns a live web view into a URL-only placeholder that
/// reloads when shown again.
///
/// Generic and UI-free so the state machine is unit-testable; the app supplies
/// what "live" and "demote" mean.
public struct PageStack<Element> {
    public private(set) var back: [Element] = []
    public private(set) var forward: [Element] = []

    private let liveLimit: Int
    private let isLive: (Element) -> Bool
    private let demote: (Element) -> Element

    public init(liveLimit: Int,
                isLive: @escaping (Element) -> Bool,
                demote: @escaping (Element) -> Element) {
        self.liveLimit = max(0, liveLimit)
        self.isLive = isLive
        self.demote = demote
    }

    public var canGoBack: Bool { !back.isEmpty }
    public var canGoForward: Bool { !forward.isEmpty }

    /// Navigating to a new page: the current page joins the back stack and the
    /// forward stack is discarded (standard browser semantics). Returns the
    /// discarded forward elements so the caller can tear them down.
    @discardableResult
    public mutating func push(current: Element) -> [Element] {
        back.append(current)
        back = Self.demotingOverflow(back, limit: liveLimit, isLive: isLive, demote: demote)
        let dropped = forward
        forward = []
        return dropped
    }

    /// Go back one page: the current page joins the forward stack; returns the
    /// page to show, or nil when there is nowhere to go back to.
    public mutating func goBack(current: Element) -> Element? {
        guard let target = back.popLast() else { return nil }
        forward.append(current)
        forward = Self.demotingOverflow(forward, limit: liveLimit, isLive: isLive, demote: demote)
        return target
    }

    /// Go forward one page (mirror of `goBack`).
    public mutating func goForward(current: Element) -> Element? {
        guard let target = forward.popLast() else { return nil }
        back.append(current)
        back = Self.demotingOverflow(back, limit: liveLimit, isLive: isLive, demote: demote)
        return target
    }

    /// Demote matching live elements in both stacks (e.g. a background page whose
    /// WebContent process was terminated) so they reload when shown again.
    public mutating func demoteAll(where predicate: (Element) -> Bool) {
        back = back.map { predicate($0) && isLive($0) ? demote($0) : $0 }
        forward = forward.map { predicate($0) && isLive($0) ? demote($0) : $0 }
    }

    /// Demote live elements from the bottom (farthest from the current page)
    /// until at most `limit` live elements remain.
    private static func demotingOverflow(_ stack: [Element], limit: Int,
                                         isLive: (Element) -> Bool,
                                         demote: (Element) -> Element) -> [Element] {
        var live = stack.reduce(0) { $0 + (isLive($1) ? 1 : 0) }
        guard live > limit else { return stack }
        return stack.map { element in
            guard live > limit, isLive(element) else { return element }
            live -= 1
            return demote(element)
        }
    }
}
