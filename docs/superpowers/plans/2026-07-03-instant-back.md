# 즉시 뒤로가기 (페이지 스택) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Link clicks keep the current page alive on a per-tab stack and load in a fresh web view, so back/forward is instant (zero network, scroll/DOM preserved).

**Architecture:** A pure generic `PageStack` state machine in MiniBrowserCore (unit-tested) manages back/forward stacks with a live-web-view cap and demotion to URL placeholders. `Tab` owns a `PageStack<StackedPage>` and swaps its `webView` using the existing rebuild/re-attach machinery. `WebView.Coordinator` intercepts main-frame `linkActivated` navigations and routes them to `Tab.pushNewPage(loading:)`. A new `TwoFingerSwipe` local scroll-event monitor adds trackpad swipe over the stack.

**Tech Stack:** Swift 6.3 Swift Package, SwiftUI + WKWebView, XCTest. No new dependencies.

**Design spec:** `docs/superpowers/specs/2026-07-03-instant-back-design.md`

## Global Constraints

- Live cap: **5** live web views per stack direction (back / forward); overflow demoted farthest-from-current first (stack bottom).
- Only **main-frame `linkActivated` http/https** navigations are stacked; fragment jumps within the same document, form posts, redirects, JS navigation stay in the current web view (native history).
- Back/forward routing: native in-page history first (`webView.canGoBack`), then the stack.
- Pushing a new page **clears the forward stack** (standard browser semantics).
- Session persistence unchanged: only the current URL/title/zoom/inverted is saved; the stack is not restored across launches.
- Code comments in English (codebase style); user-visible strings in Korean.
- Tests: `swift test` (SPM). Never run the app via bare `swift run` — use `./scripts/run.sh` (WKWebView needs a bundle).
- Target: macOS 26, Apple Silicon. `WKWebView` is main-actor; `Tab` is `@MainActor`.
- Commit after each task with a conventional-commit message ending in the Claude co-author trailer.

---

### Task 1: `PageStack` state machine (MiniBrowserCore, TDD)

**Files:**
- Create: `Sources/MiniBrowserCore/PageStack.swift`
- Test: `Tests/MiniBrowserCoreTests/PageStackTests.swift`

**Interfaces:**
- Consumes: nothing (pure Foundation).
- Produces (used by Task 3):
  ```swift
  public struct PageStack<Element> {
      public init(liveLimit: Int, isLive: @escaping (Element) -> Bool, demote: @escaping (Element) -> Element)
      public private(set) var back: [Element]
      public private(set) var forward: [Element]
      public var canGoBack: Bool
      public var canGoForward: Bool
      @discardableResult public mutating func push(current: Element) -> [Element]  // returns dropped forward
      public mutating func goBack(current: Element) -> Element?
      public mutating func goForward(current: Element) -> Element?
      public mutating func demoteAll(where predicate: (Element) -> Bool)
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/MiniBrowserCoreTests/PageStackTests.swift
import XCTest
@testable import MiniBrowserCore

final class PageStackTests: XCTestCase {
    /// Test element: a page that is either alive or demoted to a name-only shell.
    private enum P: Equatable {
        case live(String)
        case dead(String)
        var isLive: Bool { if case .live = self { return true }; return false }
        var name: String { switch self { case .live(let n), .dead(let n): return n } }
    }

    private func makeStack(limit: Int = 5) -> PageStack<P> {
        PageStack(liveLimit: limit, isLive: { $0.isLive }, demote: { .dead($0.name) })
    }

    func testPushThenBackReturnsPushedPage() {
        var s = makeStack()
        s.push(current: .live("A"))
        XCTAssertTrue(s.canGoBack)
        XCTAssertEqual(s.goBack(current: .live("B")), .live("A"))
        XCTAssertTrue(s.canGoForward)          // B moved to forward
        XCTAssertFalse(s.canGoBack)
    }

    func testBackForwardRoundTripPreservesOrder() {
        var s = makeStack()
        s.push(current: .live("A"))
        s.push(current: .live("B"))                                  // back=[A,B]
        XCTAssertEqual(s.goBack(current: .live("C")), .live("B"))    // forward=[C]
        XCTAssertEqual(s.goBack(current: .live("B")), .live("A"))    // forward=[C,B]
        XCTAssertNil(s.goBack(current: .live("A")))
        XCTAssertEqual(s.goForward(current: .live("A")), .live("B"))
        XCTAssertEqual(s.goForward(current: .live("B")), .live("C"))
        XCTAssertNil(s.goForward(current: .live("C")))
        XCTAssertEqual(s.back, [.live("A"), .live("B")])
    }

    func testGoBackOnEmptyLeavesForwardUntouched() {
        var s = makeStack()
        s.push(current: .live("A"))
        _ = s.goBack(current: .live("B"))                            // forward=[B]
        XCTAssertNil(s.goBack(current: .live("A")))
        XCTAssertEqual(s.forward, [.live("B")])
    }

    func testPushClearsForwardAndReturnsDropped() {
        var s = makeStack()
        s.push(current: .live("A"))
        _ = s.goBack(current: .live("B"))                            // forward=[B]
        let dropped = s.push(current: .live("A"))                    // new navigation from A
        XCTAssertEqual(dropped, [.live("B")])
        XCTAssertFalse(s.canGoForward)
        XCTAssertEqual(s.back, [.live("A")])
    }

    func testLiveLimitDemotesFarthestOnBackStack() {
        var s = makeStack(limit: 2)
        s.push(current: .live("A"))
        s.push(current: .live("B"))
        s.push(current: .live("C"))                                  // 3 live > 2
        XCTAssertEqual(s.back, [.dead("A"), .live("B"), .live("C")])
        s.push(current: .live("D"))
        XCTAssertEqual(s.back, [.dead("A"), .dead("B"), .live("C"), .live("D")])
    }

    func testLiveLimitDemotesFarthestOnForwardStack() {
        var s = makeStack(limit: 1)
        s.push(current: .live("A"))
        s.push(current: .live("B"))                                  // back=[dead A, live B]
        XCTAssertEqual(s.goBack(current: .live("C")), .live("B"))    // forward=[C]
        XCTAssertEqual(s.goBack(current: .live("D")), .dead("A"))    // forward=[C,D] -> demote C
        XCTAssertEqual(s.forward, [.dead("C"), .live("D")])
        XCTAssertFalse(s.canGoBack)
    }

    func testDemoteAllWhereMatches() {
        var s = makeStack()
        s.push(current: .live("A"))
        s.push(current: .live("B"))
        _ = s.goBack(current: .live("C"))                            // back=[A], forward=[C]
        s.demoteAll { $0.name == "A" || $0.name == "C" }
        XCTAssertEqual(s.back, [.dead("A")])
        XCTAssertEqual(s.forward, [.dead("C")])
    }

    func testCanGoFlagsStartFalse() {
        let s = makeStack()
        XCTAssertFalse(s.canGoBack)
        XCTAssertFalse(s.canGoForward)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PageStackTests`
Expected: compile FAILURE — `cannot find 'PageStack' in scope`

- [ ] **Step 3: Write the implementation**

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PageStackTests`
Expected: `Executed 8 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add Sources/MiniBrowserCore/PageStack.swift Tests/MiniBrowserCoreTests/PageStackTests.swift
git commit -m "feat(core): PageStack — capped live back/forward stacks with demotion"
```

---

### Task 2: `LinkNavigation.shouldStack` classifier (MiniBrowserCore, TDD)

**Files:**
- Create: `Sources/MiniBrowserCore/LinkNavigation.swift`
- Test: `Tests/MiniBrowserCoreTests/LinkNavigationTests.swift`

**Interfaces:**
- Consumes: nothing (pure Foundation).
- Produces (used by Task 4):
  ```swift
  public enum LinkNavigation {
      public static func shouldStack(url: URL, currentURL: URL?) -> Bool
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/MiniBrowserCoreTests/LinkNavigationTests.swift
import XCTest
@testable import MiniBrowserCore

final class LinkNavigationTests: XCTestCase {
    private func url(_ s: String) -> URL { URL(string: s)! }

    func testDifferentPageStacks() {
        XCTAssertTrue(LinkNavigation.shouldStack(url: url("https://a.com/post/2"),
                                                 currentURL: url("https://a.com/list")))
    }

    func testQueryChangeStacks() {
        XCTAssertTrue(LinkNavigation.shouldStack(url: url("https://a.com/list?page=2"),
                                                 currentURL: url("https://a.com/list")))
    }

    func testIdenticalURLWithoutFragmentStacks() {
        // Re-clicking a link to the current page reloads it as a new entry, like a browser.
        XCTAssertTrue(LinkNavigation.shouldStack(url: url("https://a.com/list"),
                                                 currentURL: url("https://a.com/list")))
    }

    func testFragmentJumpSameDocumentDoesNotStack() {
        XCTAssertFalse(LinkNavigation.shouldStack(url: url("https://a.com/post#comments"),
                                                  currentURL: url("https://a.com/post")))
    }

    func testFragmentToFragmentSameDocumentDoesNotStack() {
        XCTAssertFalse(LinkNavigation.shouldStack(url: url("https://a.com/post#b"),
                                                  currentURL: url("https://a.com/post#a")))
    }

    func testFragmentOnDifferentPageStacks() {
        XCTAssertTrue(LinkNavigation.shouldStack(url: url("https://a.com/other#c"),
                                                 currentURL: url("https://a.com/post")))
    }

    func testFragmentWithNilCurrentStacks() {
        XCTAssertTrue(LinkNavigation.shouldStack(url: url("https://a.com/post#c"), currentURL: nil))
    }

    func testJavascriptSchemeDoesNotStack() {
        XCTAssertFalse(LinkNavigation.shouldStack(url: url("javascript:void(0)"),
                                                  currentURL: url("https://a.com")))
    }

    func testMailtoDoesNotStack() {
        XCTAssertFalse(LinkNavigation.shouldStack(url: url("mailto:x@y.com"),
                                                  currentURL: url("https://a.com")))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LinkNavigationTests`
Expected: compile FAILURE — `cannot find 'LinkNavigation' in scope`

- [ ] **Step 3: Write the implementation**

```swift
// Sources/MiniBrowserCore/LinkNavigation.swift
import Foundation

/// Classifies a clicked link: should it be *stacked* (loaded in a fresh web view,
/// keeping the current page alive for instant back) or left to the current web
/// view (same-document fragment jumps, non-web schemes)?
public enum LinkNavigation {
    public static func shouldStack(url: URL, currentURL: URL?) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false   // javascript:, mailto:, … — let WebKit handle in place
        }
        // A fragment jump within the same document must stay in-page (no load at all).
        if url.fragment != nil, let currentURL,
           strippingFragment(url) == strippingFragment(currentURL) {
            return false
        }
        return true
    }

    private static func strippingFragment(_ url: URL) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.url
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LinkNavigationTests`
Expected: `Executed 9 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add Sources/MiniBrowserCore/LinkNavigation.swift Tests/MiniBrowserCoreTests/LinkNavigationTests.swift
git commit -m "feat(core): LinkNavigation.shouldStack — classify stackable link clicks"
```

---

### Task 3: `StackedPage` + `Tab` page-stack integration

**Files:**
- Create: `Sources/MiniBrowserApp/StackedPage.swift`
- Modify: `Sources/MiniBrowserApp/Tab.swift`

**Interfaces:**
- Consumes: `PageStack` from Task 1 (`import MiniBrowserCore` already present in Tab.swift).
- Produces (used by Tasks 4–5):
  - `Tab.pushNewPage(loading url: URL)` — stack current page, load `url` in a fresh web view.
  - `Tab.backgroundPageDied(_ wv: WKWebView)` — demote a stacked page whose process died.
  - `Tab.goBack()` / `Tab.goForward()` — now stack-aware (signatures unchanged).
  - `Tab.canGoBack` / `Tab.canGoForward` — now `native ‖ stack` (published, unchanged names).

- [ ] **Step 1: Create `StackedPage`**

```swift
// Sources/MiniBrowserApp/StackedPage.swift
import WebKit

/// One entry in a tab's page stack: a page kept fully alive (web view retained,
/// DOM/scroll intact) or, once evicted by the live cap, a URL-only placeholder
/// that reloads when the user navigates back to it.
struct StackedPage {
    /// nil = placeholder (page must reload when shown again).
    var webView: WKWebView?
    let url: URL?
    let title: String

    var isLive: Bool { webView != nil }
    func demoted() -> StackedPage { StackedPage(webView: nil, url: url, title: title) }
}
```

- [ ] **Step 2: Add the stack to `Tab`**

In `Tab.swift`, after the `private var kvo: [NSKeyValueObservation] = []` line, add:

```swift
    /// Pages kept alive for instant back/forward. Capped at 5 live web views per
    /// direction; older entries become URL placeholders that reload when shown.
    private var pageStack = PageStack<StackedPage>(
        liveLimit: 5,
        isLive: { $0.isLive },
        demote: { $0.demoted() })
```

- [ ] **Step 3: Route back/forward through the stack**

Replace the two lines

```swift
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
```

with:

```swift
    /// Back/forward: in-page (native) history wins when the current web view has
    /// it; otherwise swap in the live page from the stack — instant, no network.
    func goBack() {
        if webView.canGoBack { webView.goBack(); return }
        guard let target = pageStack.goBack(current: currentPage()) else { return }
        show(target)
    }

    func goForward() {
        if webView.canGoForward { webView.goForward(); return }
        guard let target = pageStack.goForward(current: currentPage()) else { return }
        show(target)
    }
```

- [ ] **Step 4: Add the page-stack section (push/show/adopt)**

Add after `reattachLoad()` (before `handleLoaded`):

```swift
    // MARK: page stack (instant back/forward)

    /// A link was clicked: keep the current page alive on the back stack and load
    /// the URL in a fresh web view shown in its place — so going back is instant.
    func pushNewPage(loading url: URL) {
        pageStack.push(current: currentPage())   // dropped forward pages release here
        adoptFresh(Self.makeWebView(WKWebViewConfiguration()))
        loadError = nil
        pendingURL = url              // loaded by reattachLoad() once the new view attaches
        objectWillChange.send()       // swap the new web view into the view hierarchy
    }

    /// A stacked (background) page's WebContent process was terminated (e.g.
    /// memory pressure): demote it so it reloads when shown instead of being blank.
    func backgroundPageDied(_ wv: WKWebView) {
        pageStack.demoteAll { $0.webView === wv }
    }

    private func currentPage() -> StackedPage {
        StackedPage(webView: webView, url: webView.url ?? pendingURL, title: title)
    }

    /// Display a page coming off the stack: live pages appear as-is (DOM/scroll
    /// preserved); placeholders get a fresh web view and reload their URL.
    private func show(_ page: StackedPage) {
        loadError = nil
        if let live = page.webView {
            adopt(live)
            live.pageZoom = zoom      // zoom/invert may have changed while stacked
            installInvertScript()
            applyInvert()
        } else {
            adoptFresh(Self.makeWebView(WKWebViewConfiguration()))
            pendingURL = page.url
            url = page.url
            title = page.title
        }
        objectWillChange.send()       // swap the web view into the view hierarchy
    }

    /// Make `newView` the tab's current web view: move KVO over and re-sync the
    /// published state that KVO (registered without .initial) won't fire for.
    private func adopt(_ newView: WKWebView) {
        kvo.forEach { $0.invalidate() }; kvo = []
        webView = newView
        observe()
        if let u = newView.url {      // live page: sync display state from the view
            url = u
            title = newView.title ?? ""
        }                             // fresh view: keep current url/title until it loads
        isLoading = newView.isLoading
        progress = newView.estimatedProgress
        syncNavFlags()
    }

    /// `adopt` for a brand-new web view: also register blockers and appearance.
    private func adoptFresh(_ newView: WKWebView) {
        AdBlocker.shared.register(newView)
        ElementHider.shared.register(newView)
        newView.pageZoom = zoom
        adopt(newView)
        if inverted { installInvertScript() }
    }

    /// Tab-level back/forward availability = native in-page history OR the stack.
    private func syncNavFlags() {
        canGoBack = webView.canGoBack || pageStack.canGoBack
        canGoForward = webView.canGoForward || pageStack.canGoForward
    }
```

- [ ] **Step 5: Make KVO nav flags stack-aware**

In `observe()`, replace the `canGoBack` / `canGoForward` observation entries:

```swift
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.syncNavFlags() }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.syncNavFlags() }
            },
```

- [ ] **Step 6: Reuse `adoptFresh` in the recovery rebuild**

Replace the body of `rebuildWebView(loading:afterDelay:)`:

```swift
    /// Swap in a brand-new web view, preserving zoom/inversion; back/forward history
    /// is reset. The load is deferred (see `reattachLoad`) so it happens once the new
    /// view is mounted; `delay` additionally lets a wedged connection age out.
    private func rebuildWebView(loading target: URL?, afterDelay delay: Double) {
        adoptFresh(Self.makeWebView(WKWebViewConfiguration()))
        pendingURL = target           // loaded by reattachLoad() once the new view attaches
        reattachDelay = delay
        objectWillChange.send()       // swap the new web view into the view hierarchy
    }
```

- [ ] **Step 7: Build and run all tests**

Run: `swift build && swift test`
Expected: build succeeds; all tests pass (67 = 58 existing + 8 PageStack + 9 LinkNavigation… run count from Tasks 1–2 already included — expect **75 total, 0 failures**).

- [ ] **Step 8: Commit**

```bash
git add Sources/MiniBrowserApp/StackedPage.swift Sources/MiniBrowserApp/Tab.swift
git commit -m "feat: Tab keeps pages alive on a PageStack for instant back/forward"
```

---

### Task 4: Intercept link clicks + background-page guards (`WebView.Coordinator`)

**Files:**
- Modify: `Sources/MiniBrowserApp/WebView.swift`

**Interfaces:**
- Consumes: `Tab.pushNewPage(loading:)`, `Tab.backgroundPageDied(_:)` (Task 3), `LinkNavigation.shouldStack` (Task 2; `import MiniBrowserCore` already present).
- Produces: no new API — behavior only.

- [ ] **Step 1: Add the navigation-policy intercept**

Add this method inside `Coordinator` (above `webView(_:didFinish:)`):

```swift
        // Link clicks load into a NEW web view so the current page stays alive on
        // the tab's page stack — going back is then instant (no reload). Fragment
        // jumps, non-web schemes, new-window targets (targetFrame == nil -> handled
        // by createWebViewWith) and the very first page stay in this web view.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let tab,
               navigationAction.navigationType == .linkActivated,
               navigationAction.targetFrame?.isMainFrame == true,
               webView === tab.webView,                    // not a stacked background page
               tab.url != nil,                             // not the tab's very first load
               let url = navigationAction.request.url,
               LinkNavigation.shouldStack(url: url, currentURL: webView.url) {
                decisionHandler(.cancel)
                tab.pushNewPage(loading: url)
                return
            }
            decisionHandler(.allow)
        }
```

- [ ] **Step 2: Ignore background (stacked) pages in `didFinish`**

At the top of `webView(_:didFinish:)`, add as the first line:

```swift
            guard webView === tab?.webView else { return }   // a stacked background page finished — ignore
```

- [ ] **Step 3: Guard `report` and process termination for background pages**

Replace `webViewWebContentProcessDidTerminate` and `report`:

```swift
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            FileHandle.standardError.write(Data("WebContent process terminated — reloading (G2)\n".utf8))
            if webView === tab?.webView {
                webView.reloadFromOrigin()   // re-fetch fresh so encoding/state is re-derived, not restored stale
            } else {
                tab?.backgroundPageDied(webView)   // demote to placeholder; reloads when shown
            }
        }
        private func report(_ error: Error, on webView: WKWebView) {
            FileHandle.standardError.write(Data("nav failed: \(error)\n".utf8))
            guard webView === tab?.webView else { return }               // background page — no overlay
            if (error as NSError).code == NSURLErrorCancelled { return }  // -999: stop()/redirects
            tab?.loadError = error.localizedDescription
        }
```

- [ ] **Step 4: Build and test**

Run: `swift build && swift test`
Expected: build succeeds, all tests pass.

- [ ] **Step 5: Manual smoke test (instant back)**

```bash
./scripts/run.sh
```
In the app: open `https://m.ppomppu.co.kr/new/`, scroll partway down the list, click a post, wait for it to load, press the bottom `‹` button.
Expected: the list reappears **instantly** (no progress bar, no network) at the **same scroll position**. Press `›`: the post reappears instantly. Click a different post from the list: forward stack clears (`›` disabled).

- [ ] **Step 6: Commit**

```bash
git add Sources/MiniBrowserApp/WebView.swift
git commit -m "feat: stack link-activated navigations; guard delegate against background pages"
```

---

### Task 5: Trackpad two-finger swipe over the stack

**Files:**
- Create: `Sources/MiniBrowserApp/TwoFingerSwipe.swift`
- Modify: `Sources/MiniBrowserApp/BrowserView.swift`

**Interfaces:**
- Consumes: `Tab.goBack()/goForward()/canGoBack/canGoForward/webView` (Task 3).
- Produces: `TwoFingerSwipe(tabProvider: @escaping () -> Tab?)` — install once per browser window; lives for the app's lifetime (no teardown needed).

- [ ] **Step 1: Create `TwoFingerSwipe`**

```swift
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
    private var mode: Mode = .idle
    private let threshold: CGFloat = 80   // accumulated horizontal points to commit

    private enum Mode { case idle, navigating, passthrough, swallowingMomentum }

    private let tabProvider: () -> Tab?

    init(tabProvider: @escaping () -> Tab?) {
        self.tabProvider = tabProvider
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) ?? event }
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
            setOffset(offset(), on: webView)
            return nil
        case .ended, .cancelled:
            guard mode == .navigating else { mode = .idle; return event }
            setOffset(0, on: webView)                          // new page renders in place
            if (goingBack ? accumX : -accumX) >= threshold {
                if goingBack { tab.goBack() } else { tab.goForward() }
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
}
```

- [ ] **Step 2: Install it in `BrowserView`**

In `BrowserView.swift`, add a state property next to `@State private var keyMonitor…`:

```swift
    @State private var twoFingerSwipe: TwoFingerSwipe?
```

In the `.onAppear` that calls `model.restore()` / `installZoomKeys()`, add:

```swift
            if twoFingerSwipe == nil {
                twoFingerSwipe = TwoFingerSwipe { [weak model] in model?.active }
            }
```

(If `model` is a non-optional stored property of the view struct, `[weak model]` works because `TabsModel` is a class.)

- [ ] **Step 3: Build and test**

Run: `swift build && swift test`
Expected: build succeeds, all tests pass.

- [ ] **Step 4: Manual smoke test**

```bash
./scripts/run.sh
```
Open ppomppu, click into a post, then swipe **two fingers right** on the trackpad over the page.
Expected: the page follows slightly, then the list appears instantly. Swipe two fingers **left**: the post returns. Vertical two-finger scrolling still scrolls normally; a page with in-page history (e.g. an SPA) still uses WebKit's native gesture.

- [ ] **Step 5: Commit**

```bash
git add Sources/MiniBrowserApp/TwoFingerSwipe.swift Sources/MiniBrowserApp/BrowserView.swift
git commit -m "feat: two-finger trackpad swipe navigates the page stack"
```

---

### Task 7: Live reveal — book-flip back/forward (added 2026-07-03, user request)

**Files:**
- Modify: `Sources/MiniBrowserCore/PageStack.swift`
- Modify: `Tests/MiniBrowserCoreTests/PageStackTests.swift`
- Modify: `Sources/MiniBrowserApp/Tab.swift`
- Modify: `Sources/MiniBrowserApp/EdgeSwipeOverlay.swift`
- Modify: `Sources/MiniBrowserApp/TwoFingerSwipe.swift`

**Interfaces:**
- Consumes: `PageStack` (Task 1), `Tab` page stack (Task 3), gesture code (Tasks 4–5).
- Produces:
  - `PageStack.backTop: Element?` / `PageStack.forwardTop: Element?` (peek, non-mutating)
  - `Tab.peekView(back: Bool) -> WKWebView?` — live web view a gesture would reveal, or nil.

- [ ] **Step 1: Write failing tests for the peek API**

Append to `Tests/MiniBrowserCoreTests/PageStackTests.swift` (inside the class):

```swift
    func testTopsPeekWithoutMutating() {
        var s = makeStack()
        XCTAssertNil(s.backTop)
        XCTAssertNil(s.forwardTop)
        s.push(current: .live("A"))
        s.push(current: .live("B"))
        XCTAssertEqual(s.backTop, .live("B"))            // what goBack() would reveal
        XCTAssertEqual(s.back, [.live("A"), .live("B")]) // unchanged by peeking
        _ = s.goBack(current: .live("C"))
        XCTAssertEqual(s.forwardTop, .live("C"))         // what goForward() would reveal
        XCTAssertEqual(s.backTop, .live("A"))
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter PageStackTests`
Expected: compile FAILURE — `value of type 'PageStack<P>' has no member 'backTop'`

- [ ] **Step 3: Implement the peek API**

In `Sources/MiniBrowserCore/PageStack.swift`, after the `canGoForward` property, add:

```swift
    /// The entry `goBack()` would reveal next (stack top), without mutating.
    public var backTop: Element? { back.last }
    /// The entry `goForward()` would reveal next (stack top), without mutating.
    public var forwardTop: Element? { forward.last }
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter PageStackTests`
Expected: `Executed 9 tests, with 0 failures`

- [ ] **Step 5: Add `Tab.peekView(back:)`**

In `Sources/MiniBrowserApp/Tab.swift`, after `backgroundPageDied(_:)`, add:

```swift
    /// The live web view a back/forward gesture would reveal — shown UNDER the
    /// current page during an interactive swipe so the real screen "flips" into
    /// view. nil when native in-page history would win (WebKit's own gesture) or
    /// when the next stack entry is a placeholder (nothing live to show).
    func peekView(back: Bool) -> WKWebView? {
        if back {
            guard !webView.canGoBack else { return nil }
            return pageStack.backTop?.webView
        }
        guard !webView.canGoForward else { return nil }
        return pageStack.forwardTop?.webView
    }
```

- [ ] **Step 6: Reveal the live page under the edge drag**

In `Sources/MiniBrowserApp/EdgeSwipeOverlay.swift`:

Add a property after `private var offset: CGFloat = 0`:

```swift
    private var peek: WKWebView?   // live page shown under the current one while swiping
```

In `mouseDragged`, replace the line `if swiping { setOffset(fromLeft ? max(0, dx) : min(0, dx)) }` with:

```swift
        if swiping {
            installPeekIfNeeded()
            setOffset(fromLeft ? max(0, dx) : min(0, dx))
        }
```

In `mouseUp`, replace the `if swiping { ... }` block with:

```swift
        if swiping {
            if (fromLeft ? dx : -dx) >= threshold() {
                setOffset(0)                 // reset before the view goes on the stack
                if fromLeft { tab?.goBack() } else { tab?.goForward() }
                peek = nil                   // the swap re-attaches subviews; nothing to remove
            } else {
                setOffset(0, animated: true) // snap back
                removePeek(afterDelay: 0.25) // keep it visible under the snap-back animation
            }
        } else if event.timestamp - downTime >= longPress {
            forwardClick(at: downPoint)       // long press -> real click
        }                                     // quick tap -> swallowed
        swiping = false
```

Add these two methods before `setOffset`:

```swift
    /// Put the live page the gesture would reveal UNDER the current web view, so
    /// dragging the page aside uncovers the real screen (book-flip effect).
    private func installPeekIfNeeded() {
        guard peek == nil, let container = superview, let current = tab?.webView,
              let target = tab?.peekView(back: fromLeft) else { return }
        target.frame = container.bounds
        target.autoresizingMask = [.width, .height]
        container.addSubview(target, positioned: .below, relativeTo: current)
        peek = target
    }

    private func removePeek(afterDelay delay: TimeInterval) {
        guard let peek else { return }
        self.peek = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { peek.removeFromSuperview() }
    }
```

In `draw(_:)`, add as the first line (the real page underneath is a better hint than the chevron):

```swift
        guard peek == nil else { return }
```

- [ ] **Step 7: Same reveal for the two-finger swipe**

In `Sources/MiniBrowserApp/TwoFingerSwipe.swift`:

Add a property after `private var goingBack = true`:

```swift
    private var peek: WKWebView?   // live page shown under the current one while swiping
```

In `handle(_:)`, in the `.changed` case, replace:

```swift
            guard mode == .navigating else { return event }
            setOffset(offset(), on: webView)
            return nil
```

with:

```swift
            guard mode == .navigating else { return event }
            installPeekIfNeeded(tab: tab, under: webView)
            setOffset(offset(), on: webView)
            return nil
```

In the `.ended, .cancelled` case, replace:

```swift
            setOffset(0, on: webView)                          // new page renders in place
            if (goingBack ? accumX : -accumX) >= threshold {
                if goingBack { tab.goBack() } else { tab.goForward() }
            }
            mode = .swallowingMomentum
            return nil
```

with:

```swift
            setOffset(0, on: webView)                          // reset before any stack swap
            if (goingBack ? accumX : -accumX) >= threshold {
                if goingBack { tab.goBack() } else { tab.goForward() }
                peek = nil                                     // swap re-attaches subviews
            } else {
                removePeek(afterDelay: 0.25)                   // visible under the snap-back
            }
            mode = .swallowingMomentum
            return nil
```

Add these two methods after `setOffset(_:on:)`:

```swift
    /// Put the live page the gesture would reveal UNDER the current web view
    /// (book-flip effect, same as the edge drag).
    private func installPeekIfNeeded(tab: Tab, under webView: WKWebView) {
        guard peek == nil, let container = webView.superview,
              let target = tab.peekView(back: goingBack) else { return }
        target.frame = container.bounds
        target.autoresizingMask = [.width, .height]
        container.addSubview(target, positioned: .below, relativeTo: webView)
        peek = target
    }

    private func removePeek(afterDelay delay: TimeInterval) {
        guard let peek else { return }
        self.peek = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { peek.removeFromSuperview() }
    }
```

- [ ] **Step 8: Build and full test run**

Run: `swift build && swift test`
Expected: clean build, 76 tests, 0 failures.

- [ ] **Step 9: Commit**

```bash
git add Sources/MiniBrowserCore/PageStack.swift Tests/MiniBrowserCoreTests/PageStackTests.swift \
        Sources/MiniBrowserApp/Tab.swift Sources/MiniBrowserApp/EdgeSwipeOverlay.swift \
        Sources/MiniBrowserApp/TwoFingerSwipe.swift
git commit -m "feat: live book-flip reveal — real previous page shows under back/forward swipes"
```

---

### Task 6: End-to-end verification, regressions, push

**Files:** none (verification only; fix-forward commits if issues found).

- [ ] **Step 1: Full test suite**

Run: `swift test`
Expected: all tests pass, 0 failures.

- [ ] **Step 2: Instant-back E2E on real sites**

`./scripts/run.sh`, then verify each (screenshot or observe):
1. ppomppu list → post → `‹` button: list instant, same scroll offset.
2. Edge-drag from left 60pt strip: same instant back.
3. Two-finger swipe right: same instant back; swipe left: forward instant.
4. Chain 7 links deep, then go back 7 times: the 2 oldest pages reload (placeholders — cap is 5), the rest are instant.
5. Fragment link (e.g. a `#comments`/맨위로 in-page anchor): jumps in place, does NOT reload or push.

- [ ] **Step 3: Regression sweep**

1. `target=_blank` link still opens a new tab.
2. 새 탭 → start page → bookmark click loads normally.
3. Zoom (`Cmd +/-`) and 색 반전 survive back/forward swaps (revealed page gets current zoom/invert).
4. 강제 리셋 (글자 깨짐 복구) still rebuilds only the current page; back stack survives.
5. Quit and relaunch: session restores current pages (stack empty — expected), titles kept.
6. Tab switcher: titles/hosts still correct after several back/forwards.

- [ ] **Step 4: Push**

```bash
git push origin main
```

---

## Self-Review Notes

- **Spec coverage:** push rule (Task 4 Step 1), native-first routing (Task 3 Step 3), forward clearing + cap 5 both directions (Task 1), placeholder revival (Task 3 `show`), canGo flags (Task 3 Steps 4–5), edge swipe unchanged (uses `tab.canGoBack`/`tab.goBack()` — stack-aware automatically), two-finger (Task 5), unchanged persistence (no changes made), trade-offs accepted in spec. Live-reveal explicitly out of scope.
- **Type consistency:** `StackedPage` fields (`webView/url/title`), `PageStack` API, `pushNewPage(loading:)`, `backgroundPageDied(_:)` used identically across Tasks 3–5.
- **Known accepted quirks:** window.open-created tabs lose `window.opener` linkage for subsequent stacked pages (fresh `WKWebViewConfiguration`); background stacked pages keep running JS until evicted.
