# miniBrowser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS SwiftUI + WKWebView "mini browser" that looks and scrolls like iPhone Safari, with tabs, bookmarks/start page, and history — built as a Swift Package run via `swift run` / `swift test`.

**Architecture:** Three SwiftPM targets. `MiniBrowserCore` (library) holds all pure, WebKit-free logic and is the only thing unit-tested. `MiniBrowserApp` (executable) is a thin SwiftUI shell that owns WKWebView instances and calls into Core. `MiniBrowserCoreTests` tests Core. The app is launched as a minimal `.app` bundle (required for WKWebView's WebContent process to start) via `scripts/run.sh`.

**Tech Stack:** Swift 6.3, SwiftUI, AppKit (NSApplication/NSViewRepresentable), WebKit (WKWebView), XCTest. No external dependencies.

## Global Constraints

These apply to **every** task. Values copied verbatim from the spec.

- **swift-tools-version:** `6.3`. First line of `Package.swift`.
- **Platform:** `platforms: [.macOS(.v26)]`. If the toolchain rejects `.v26`, fall back to `.macOS("26.0")`.
- **Targets:** `MiniBrowserCore` (library, all logic, `public` API), `MiniBrowserApp` (executableTarget, depends on Core, `@main`), `MiniBrowserCoreTests` (testTarget, depends on Core **only** — never the executable).
- **No external dependencies.** `dependencies: []`.
- **G1 — Activation bootstrap (MANDATORY):** the `@main App` `init()` must, on the main queue, call `NSApp.setActivationPolicy(.regular)`, `NSApp.activate()` (NOT the deprecated `activate(ignoringOtherApps:)`), and bring the window frontmost. Without this the address bar cannot receive keyboard input.
- **G2 — `.app` bundle required:** run via `scripts/run.sh`, which wraps the built binary in `.build/miniBrowser.app` with an `Info.plist` containing non-empty `CFBundleIdentifier` = `dev.gum798.miniBrowser` and `CFBundleDisplayName` = `miniBrowser`. Bundle-less `swift run` may produce a blank web view (WebContent process fails to launch).
- **G3 — Mobile rendering:** set `webView.customUserAgent` to the iPhone Safari UA **before loading**, and constrain the web view width to ~390pt. Do NOT use `preferredContentMode` (iOS-only). UA string:
  `Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1`
- **G4 — Per-tab WKWebView persistence:** a reference-type `Tab: ObservableObject` permanently owns its `WKWebView`; the `NSViewRepresentable` swaps the active tab's existing web view into a container, never recreates it. KVO tokens invalidated in `Tab.deinit`; Coordinator holds the model `weak`.
- **Do NOT** enable App Sandbox or add `com.apple.security.network.client` for the local build. Do NOT strip the linker ad-hoc signature.
- **Default search engine:** Google. **Persistence dir:** `~/Library/Application Support/miniBrowser/`.

---

## File Structure

```
MiniBrowser/
├── Package.swift
├── scripts/run.sh                      # build → .app wrap → open  (Task 1, used by Tasks 2/8/9/10)
├── Sources/
│   ├── MiniBrowserCore/
│   │   ├── SearchEngine.swift          # Task 3
│   │   ├── URLResolver.swift           # Task 3
│   │   ├── MobileUserAgent.swift       # Task 3
│   │   ├── Bookmark.swift              # Task 5
│   │   ├── BookmarkStore.swift         # Task 5
│   │   ├── HistoryEntry.swift          # Task 6
│   │   ├── HistoryStore.swift          # Task 6
│   │   └── TabsState.swift             # Task 7
│   └── MiniBrowserApp/
│       ├── MiniBrowserApp.swift        # Task 2 (G1), grows in Task 8
│       ├── AppPaths.swift              # Task 8
│       ├── Tab.swift                   # Task 9 (G4)  [minimal WebView host in Task 2]
│       ├── TabsModel.swift             # Task 9
│       ├── WebView.swift               # Task 2 (G2/G3), rewritten for tabs in Task 9 (G4)
│       ├── BrowserView.swift           # Task 8, extended Tasks 9/10
│       ├── AddressBar.swift            # Task 8
│       ├── BottomToolbar.swift         # Task 8, extended Tasks 9/10
│       ├── TabSwitcherView.swift       # Task 9
│       └── StartPageView.swift         # Task 10
└── Tests/
    └── MiniBrowserCoreTests/
        ├── URLResolverTests.swift      # Task 3
        ├── BookmarkStoreTests.swift    # Task 5
        ├── HistoryStoreTests.swift     # Task 6
        └── TabsStateTests.swift        # Task 7
```

---

## Task 1: Package scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/MiniBrowserCore/Placeholder.swift`
- Create: `Tests/MiniBrowserCoreTests/SmokeTests.swift`
- Create: `scripts/run.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: a buildable 3-target package; `scripts/run.sh` (used by later GUI tasks).

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "MiniBrowser",
    platforms: [
        .macOS(.v26)   // fallback if rejected by toolchain: .macOS("26.0")
    ],
    products: [
        .library(name: "MiniBrowserCore", targets: ["MiniBrowserCore"])
    ],
    dependencies: [],
    targets: [
        .target(name: "MiniBrowserCore"),
        .executableTarget(
            name: "MiniBrowserApp",
            dependencies: [.target(name: "MiniBrowserCore")]
        ),
        .testTarget(
            name: "MiniBrowserCoreTests",
            dependencies: [.target(name: "MiniBrowserCore")]
        )
    ]
)
```

- [ ] **Step 2: Create a temporary Core source so the library compiles**

`Sources/MiniBrowserCore/Placeholder.swift`:
```swift
// Temporary anchor so the target has a source file. Removed in Task 3.
enum _Placeholder {}
```

- [ ] **Step 3: Create a temporary test so the test target compiles**

`Tests/MiniBrowserCoreTests/SmokeTests.swift`:
```swift
import XCTest
@testable import MiniBrowserCore

final class SmokeTests: XCTestCase {
    func testPackageBuilds() {
        XCTAssertTrue(true)
    }
}
```

> Note: the executable target needs an entry point to build. It is created in Task 2. If `swift build` complains that `MiniBrowserApp` has no main entry, proceed to Task 2 first, then return to verify. To keep Task 1 self-contained, also create the minimal app entry now:

`Sources/MiniBrowserApp/MiniBrowserApp.swift`:
```swift
import SwiftUI

@main
struct MiniBrowserApp: App {
    var body: some Scene {
        WindowGroup { Text("placeholder") }
    }
}
```

- [ ] **Step 4: Create `scripts/run.sh` (G2 — `.app` wrapping)**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONFIG="${1:-debug}"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="$ROOT/.build/miniBrowser.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/MiniBrowserApp" "$APP/Contents/MacOS/miniBrowser"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>miniBrowser</string>
  <key>CFBundleDisplayName</key><string>miniBrowser</string>
  <key>CFBundleIdentifier</key><string>dev.gum798.miniBrowser</string>
  <key>CFBundleExecutable</key><string>miniBrowser</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "Launching $APP"
open "$APP"
```

Then make it executable:
```bash
chmod +x scripts/run.sh
```

- [ ] **Step 5: Verify build and tests**

Run: `swift build`
Expected: builds with no errors (a deprecation/placeholder warning is fine).

Run: `swift test --filter SmokeTests`
Expected: PASS (1 test).

> If `.macOS(.v26)` is rejected, change it to `.macOS("26.0")` and re-run.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests scripts
git commit -m "chore: scaffold SwiftPM package (Core/App/Tests) + run.sh"
```

---

## Task 2: M0 foundation smoke test (G1 + G2 + G3)

**This is a de-risking spike, not unit-tested.** It proves the verified foundations actually hold on this machine before building real features. If it fails, stop and reconsider the design.

**Files:**
- Modify: `Sources/MiniBrowserApp/MiniBrowserApp.swift`
- Create: `Sources/MiniBrowserApp/WebView.swift`

**Interfaces:**
- Consumes: nothing from Core yet.
- Produces: `SmokeWebView` (NSViewRepresentable) — replaced in Task 9. The `@main` activation bootstrap pattern (kept for the life of the app).

- [ ] **Step 1: Replace `MiniBrowserApp.swift` with the activation bootstrap (G1) + a focusable field + a web view**

```swift
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
```

- [ ] **Step 2: Create `WebView.swift` with a minimal WKWebView (G2 diagnostics + G3 UA)**

```swift
import SwiftUI
import WebKit

struct SmokeWebView: NSViewRepresentable {
    let urlString: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        // G3: mobile UA must be set BEFORE loading.
        webView.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
        webView.navigationDelegate = context.coordinator
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        // G2 diagnostics: if the WebContent process dies, the bundle metadata is wrong.
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            FileHandle.standardError.write(Data("nav failed: \(error)\n".utf8))
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            FileHandle.standardError.write(Data("WebContent process terminated — check .app bundle metadata (G2)\n".utf8))
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 4: Launch via the `.app` wrapper (G2) and verify manually**

Run: `./scripts/run.sh`
Expected — confirm ALL of these:
1. A phone-sized window appears **frontmost** with a **Dock icon** (G1).
2. You can click the text field and **type into it** (G1 keyboard focus).
3. The Google page **loads and renders in mobile layout** (G2 web process launched + G3 mobile UA). The view is NOT blank.
4. No `WebContent process terminated` line in the terminal (G2).

> If the web view is blank and you see the `WebContent process terminated` / `web process failed to launch` message: the `.app` Info.plist metadata is the cause. Verify `CFBundleIdentifier`/`CFBundleDisplayName` are present and non-empty in `.build/miniBrowser.app/Contents/Info.plist`. Do NOT add App Sandbox or signing.

- [ ] **Step 5: Commit**

```bash
git add Sources/MiniBrowserApp
git commit -m "feat: M0 smoke test — activation bootstrap + WKWebView mobile load"
```

---

## Task 3: URLResolver + SearchEngine + MobileUserAgent (Core)

**Files:**
- Create: `Sources/MiniBrowserCore/SearchEngine.swift`
- Create: `Sources/MiniBrowserCore/URLResolver.swift`
- Create: `Sources/MiniBrowserCore/MobileUserAgent.swift`
- Delete: `Sources/MiniBrowserCore/Placeholder.swift`
- Test: `Tests/MiniBrowserCoreTests/URLResolverTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum SearchEngine: String, Codable, CaseIterable, Sendable { case google }` with `func searchURL(query: String) -> URL`.
  - `enum URLResolver { static func resolve(_ input: String, searchEngine: SearchEngine = .google) -> URL? }`.
  - `enum MobileUserAgent { static let iPhoneSafari: String }`.

- [ ] **Step 1: Write the failing tests**

`Tests/MiniBrowserCoreTests/URLResolverTests.swift`:
```swift
import XCTest
@testable import MiniBrowserCore

final class URLResolverTests: XCTestCase {
    func testEmptyReturnsNil() {
        XCTAssertNil(URLResolver.resolve("   "))
        XCTAssertNil(URLResolver.resolve(""))
    }

    func testExplicitSchemePassThrough() {
        XCTAssertEqual(URLResolver.resolve("https://a.com/x")?.absoluteString, "https://a.com/x")
        XCTAssertEqual(URLResolver.resolve("http://a.com")?.absoluteString, "http://a.com")
    }

    func testBareDomainGetsHttps() {
        XCTAssertEqual(URLResolver.resolve("example.com")?.absoluteString, "https://example.com")
    }

    func testLocalhostWithPort() {
        XCTAssertEqual(URLResolver.resolve("localhost:8080")?.absoluteString, "https://localhost:8080")
    }

    func testSingleWordBecomesSearch() {
        let url = URLResolver.resolve("swift")
        XCTAssertEqual(url?.absoluteString, "https://www.google.com/search?q=swift")
    }

    func testPhraseBecomesEncodedSearch() {
        let url = URLResolver.resolve("hello world")
        XCTAssertEqual(url?.absoluteString, "https://www.google.com/search?q=hello%20world")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter URLResolverTests`
Expected: FAIL — "cannot find 'URLResolver' in scope".

- [ ] **Step 3: Implement `SearchEngine`, `MobileUserAgent`, `URLResolver`; delete the placeholder**

`Sources/MiniBrowserCore/SearchEngine.swift`:
```swift
import Foundation

public enum SearchEngine: String, Codable, CaseIterable, Sendable {
    case google

    public func searchURL(query: String) -> URL {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        switch self {
        case .google:
            return URL(string: "https://www.google.com/search?q=\(encoded)")!
        }
    }
}
```

`Sources/MiniBrowserCore/MobileUserAgent.swift`:
```swift
public enum MobileUserAgent {
    /// G3: iPhone Safari UA. OS token frozen at 18_6 on iOS/macOS 26; bump only `Version/` over time.
    public static let iPhoneSafari =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
}
```

`Sources/MiniBrowserCore/URLResolver.swift`:
```swift
import Foundation

public enum URLResolver {
    public static func resolve(_ input: String, searchEngine: SearchEngine = .google) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let scheme = URL(string: trimmed)?.scheme?.lowercased(),
           ["http", "https", "file"].contains(scheme) {
            return URL(string: trimmed)
        }

        if looksLikeHost(trimmed) {
            return URL(string: "https://\(trimmed)")
        }

        return searchEngine.searchURL(query: trimmed)
    }

    private static func looksLikeHost(_ s: String) -> Bool {
        guard !s.contains(" ") else { return false }
        let hostPart = s.split(separator: "/", maxSplits: 1).first.map(String.init) ?? s
        let bare = hostPart.split(separator: ":", maxSplits: 1).first.map(String.init) ?? hostPart
        if bare == "localhost" { return true }
        guard bare.contains(".") else { return false }
        return !bare.hasPrefix(".") && !bare.hasSuffix(".")
    }
}
```

Then delete the placeholder:
```bash
rm Sources/MiniBrowserCore/Placeholder.swift
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter URLResolverTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MiniBrowserCore Tests/MiniBrowserCoreTests/URLResolverTests.swift
git commit -m "feat: URLResolver + SearchEngine + mobile UA constant"
```

---

## Task 4: AppPaths helper (App)

Small, but needed by the stores' wiring in the UI. Pure enough to be obvious; no unit test (it returns a system path).

**Files:**
- Create: `Sources/MiniBrowserApp/AppPaths.swift`

**Interfaces:**
- Produces: `enum AppPaths { static func supportDirectory() -> URL }` returning
  `~/Library/Application Support/miniBrowser/` (created if missing).

- [ ] **Step 1: Create `AppPaths.swift`**

```swift
import Foundation

enum AppPaths {
    /// ~/Library/Application Support/miniBrowser/ — created if missing.
    static func supportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("miniBrowser", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/MiniBrowserApp/AppPaths.swift
git commit -m "feat: AppPaths support directory helper"
```

---

## Task 5: Bookmark + BookmarkStore (Core)

**Files:**
- Create: `Sources/MiniBrowserCore/Bookmark.swift`
- Create: `Sources/MiniBrowserCore/BookmarkStore.swift`
- Test: `Tests/MiniBrowserCoreTests/BookmarkStoreTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct Bookmark: Codable, Identifiable, Equatable, Sendable { let id: UUID; var title: String; var url: URL; var createdAt: Date }`.
  - `final class BookmarkStore { init(directory: URL); func all() -> [Bookmark]; func add(_:); func remove(id: UUID); func move(from: Int, to: Int) }` persisting to `directory/bookmarks.json`.

- [ ] **Step 1: Write the failing tests**

`Tests/MiniBrowserCoreTests/BookmarkStoreTests.swift`:
```swift
import XCTest
@testable import MiniBrowserCore

final class BookmarkStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testAddAndAll() {
        let store = BookmarkStore(directory: tempDir())
        store.add(Bookmark(title: "Apple", url: URL(string: "https://apple.com")!))
        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(store.all().first?.title, "Apple")
    }

    func testRemove() {
        let store = BookmarkStore(directory: tempDir())
        let b = Bookmark(title: "A", url: URL(string: "https://a.com")!)
        store.add(b)
        store.remove(id: b.id)
        XCTAssertTrue(store.all().isEmpty)
    }

    func testPersistenceRoundTrip() {
        let dir = tempDir()
        let s1 = BookmarkStore(directory: dir)
        s1.add(Bookmark(title: "Z", url: URL(string: "https://z.com")!))
        let s2 = BookmarkStore(directory: dir)   // re-load from disk
        XCTAssertEqual(s2.all().count, 1)
        XCTAssertEqual(s2.all().first?.url.absoluteString, "https://z.com")
    }

    func testMoveReorders() {
        let store = BookmarkStore(directory: tempDir())
        store.add(Bookmark(title: "1", url: URL(string: "https://1.com")!))
        store.add(Bookmark(title: "2", url: URL(string: "https://2.com")!))
        store.move(from: 0, to: 1)
        XCTAssertEqual(store.all().map(\.title), ["2", "1"])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter BookmarkStoreTests`
Expected: FAIL — "cannot find 'BookmarkStore' in scope".

- [ ] **Step 3: Implement `Bookmark` and `BookmarkStore`**

`Sources/MiniBrowserCore/Bookmark.swift`:
```swift
import Foundation

public struct Bookmark: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var url: URL
    public var createdAt: Date

    public init(id: UUID = UUID(), title: String, url: URL, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.url = url
        self.createdAt = createdAt
    }
}
```

`Sources/MiniBrowserCore/BookmarkStore.swift`:
```swift
import Foundation

public final class BookmarkStore {
    private let fileURL: URL
    private var items: [Bookmark]

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("bookmarks.json")
        self.items = Self.load(from: fileURL)
    }

    public func all() -> [Bookmark] { items }

    public func add(_ bookmark: Bookmark) {
        items.append(bookmark)
        persist()
    }

    public func remove(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    public func move(from: Int, to: Int) {
        guard items.indices.contains(from), to >= 0, to <= items.count else { return }
        let item = items.remove(at: from)
        items.insert(item, at: min(to, items.count))
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> [Bookmark] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Bookmark].self, from: data)) ?? []
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter BookmarkStoreTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MiniBrowserCore/Bookmark.swift Sources/MiniBrowserCore/BookmarkStore.swift Tests/MiniBrowserCoreTests/BookmarkStoreTests.swift
git commit -m "feat: Bookmark model + JSON-backed BookmarkStore"
```

---

## Task 6: HistoryEntry + HistoryStore (Core)

**Files:**
- Create: `Sources/MiniBrowserCore/HistoryEntry.swift`
- Create: `Sources/MiniBrowserCore/HistoryStore.swift`
- Test: `Tests/MiniBrowserCoreTests/HistoryStoreTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct HistoryEntry: Codable, Equatable, Identifiable, Sendable { var id: URL { url }; let url: URL; var title: String; var lastVisited: Date; var visitCount: Int }`.
  - `final class HistoryStore { init(directory: URL); func record(url: URL, title: String, now: Date = Date()); func recent(limit: Int) -> [HistoryEntry]; func suggestions(for prefix: String, limit: Int) -> [HistoryEntry] }` persisting to `directory/history.json`.

- [ ] **Step 1: Write the failing tests**

`Tests/MiniBrowserCoreTests/HistoryStoreTests.swift`:
```swift
import XCTest
@testable import MiniBrowserCore

final class HistoryStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private func u(_ s: String) -> URL { URL(string: s)! }

    func testRecordThenRecent() {
        let store = HistoryStore(directory: tempDir())
        store.record(url: u("https://a.com"), title: "A", now: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(store.recent(limit: 10).map(\.url), [u("https://a.com")])
    }

    func testDuplicateUrlDedupesAndCounts() {
        let store = HistoryStore(directory: tempDir())
        store.record(url: u("https://a.com"), title: "A", now: Date(timeIntervalSince1970: 1))
        store.record(url: u("https://a.com"), title: "A2", now: Date(timeIntervalSince1970: 2))
        let all = store.recent(limit: 10)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.visitCount, 2)
        XCTAssertEqual(all.first?.title, "A2")            // latest title wins
        XCTAssertEqual(all.first?.lastVisited, Date(timeIntervalSince1970: 2))
    }

    func testRecentSortedByLastVisitedDescending() {
        let store = HistoryStore(directory: tempDir())
        store.record(url: u("https://a.com"), title: "A", now: Date(timeIntervalSince1970: 1))
        store.record(url: u("https://b.com"), title: "B", now: Date(timeIntervalSince1970: 5))
        XCTAssertEqual(store.recent(limit: 10).map(\.url), [u("https://b.com"), u("https://a.com")])
    }

    func testSuggestionsMatchPrefixCaseInsensitively() {
        let store = HistoryStore(directory: tempDir())
        store.record(url: u("https://apple.com"), title: "Apple", now: Date(timeIntervalSince1970: 1))
        store.record(url: u("https://google.com"), title: "Google", now: Date(timeIntervalSince1970: 2))
        let s = store.suggestions(for: "App", limit: 10)
        XCTAssertEqual(s.map(\.url), [u("https://apple.com")])
    }

    func testPersistenceRoundTrip() {
        let dir = tempDir()
        let s1 = HistoryStore(directory: dir)
        s1.record(url: u("https://z.com"), title: "Z", now: Date(timeIntervalSince1970: 1))
        let s2 = HistoryStore(directory: dir)
        XCTAssertEqual(s2.recent(limit: 10).count, 1)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter HistoryStoreTests`
Expected: FAIL — "cannot find 'HistoryStore' in scope".

- [ ] **Step 3: Implement `HistoryEntry` and `HistoryStore`**

`Sources/MiniBrowserCore/HistoryEntry.swift`:
```swift
import Foundation

public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: URL { url }
    public let url: URL
    public var title: String
    public var lastVisited: Date
    public var visitCount: Int

    public init(url: URL, title: String, lastVisited: Date, visitCount: Int) {
        self.url = url
        self.title = title
        self.lastVisited = lastVisited
        self.visitCount = visitCount
    }
}
```

`Sources/MiniBrowserCore/HistoryStore.swift`:
```swift
import Foundation

public final class HistoryStore {
    private let fileURL: URL
    private var items: [HistoryEntry]

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("history.json")
        self.items = Self.load(from: fileURL)
    }

    public func record(url: URL, title: String, now: Date = Date()) {
        if let idx = items.firstIndex(where: { $0.url == url }) {
            items[idx].title = title
            items[idx].lastVisited = now
            items[idx].visitCount += 1
        } else {
            items.append(HistoryEntry(url: url, title: title, lastVisited: now, visitCount: 1))
        }
        persist()
    }

    public func recent(limit: Int) -> [HistoryEntry] {
        Array(items.sorted { $0.lastVisited > $1.lastVisited }.prefix(limit))
    }

    public func suggestions(for prefix: String, limit: Int) -> [HistoryEntry] {
        let needle = prefix.lowercased()
        guard !needle.isEmpty else { return [] }
        return items
            .filter {
                $0.url.absoluteString.lowercased().contains(needle)
                    || $0.title.lowercased().contains(needle)
            }
            .sorted { ($0.visitCount, $0.lastVisited) > ($1.visitCount, $1.lastVisited) }
            .prefix(limit)
            .map { $0 }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter HistoryStoreTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MiniBrowserCore/HistoryEntry.swift Sources/MiniBrowserCore/HistoryStore.swift Tests/MiniBrowserCoreTests/HistoryStoreTests.swift
git commit -m "feat: HistoryEntry model + JSON-backed HistoryStore"
```

---

## Task 7: TabsState (Core)

**Files:**
- Create: `Sources/MiniBrowserCore/TabsState.swift`
- Test: `Tests/MiniBrowserCoreTests/TabsStateTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `struct TabsState: Equatable, Sendable` with `private(set) var tabIDs: [UUID]`, `private(set) var activeID: UUID?`, and mutating `add(_:)`, `select(_:)`, `close(_:)`, `move(from:to:)`.

- [ ] **Step 1: Write the failing tests**

`Tests/MiniBrowserCoreTests/TabsStateTests.swift`:
```swift
import XCTest
@testable import MiniBrowserCore

final class TabsStateTests: XCTestCase {
    func testAddMakesActive() {
        var s = TabsState()
        let a = UUID()
        s.add(a)
        XCTAssertEqual(s.tabIDs, [a])
        XCTAssertEqual(s.activeID, a)
    }

    func testClosingActiveSelectsNextNeighbor() {
        var s = TabsState()
        let a = UUID(), b = UUID(), c = UUID()
        s.add(a); s.add(b); s.add(c)   // active == c
        s.select(b)                    // active == b
        s.close(b)
        XCTAssertEqual(s.tabIDs, [a, c])
        XCTAssertEqual(s.activeID, c)  // next neighbor
    }

    func testClosingLastActiveSelectsPrevious() {
        var s = TabsState()
        let a = UUID(), b = UUID()
        s.add(a); s.add(b)             // active == b (last)
        s.close(b)
        XCTAssertEqual(s.tabIDs, [a])
        XCTAssertEqual(s.activeID, a)
    }

    func testClosingOnlyTabClearsActive() {
        var s = TabsState()
        let a = UUID()
        s.add(a)
        s.close(a)
        XCTAssertTrue(s.tabIDs.isEmpty)
        XCTAssertNil(s.activeID)
    }

    func testClosingInactiveKeepsActive() {
        var s = TabsState()
        let a = UUID(), b = UUID()
        s.add(a); s.add(b)             // active == b
        s.close(a)
        XCTAssertEqual(s.activeID, b)
        XCTAssertEqual(s.tabIDs, [b])
    }

    func testMoveReorders() {
        var s = TabsState()
        let a = UUID(), b = UUID(), c = UUID()
        s.add(a); s.add(b); s.add(c)
        s.move(from: 0, to: 2)
        XCTAssertEqual(s.tabIDs, [b, c, a])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter TabsStateTests`
Expected: FAIL — "cannot find 'TabsState' in scope".

- [ ] **Step 3: Implement `TabsState`**

`Sources/MiniBrowserCore/TabsState.swift`:
```swift
import Foundation

public struct TabsState: Equatable, Sendable {
    public private(set) var tabIDs: [UUID] = []
    public private(set) var activeID: UUID?

    public init() {}

    public mutating func add(_ id: UUID) {
        tabIDs.append(id)
        activeID = id
    }

    public mutating func select(_ id: UUID) {
        if tabIDs.contains(id) { activeID = id }
    }

    public mutating func close(_ id: UUID) {
        guard let idx = tabIDs.firstIndex(of: id) else { return }
        let wasActive = (activeID == id)
        tabIDs.remove(at: idx)
        guard wasActive else { return }
        if tabIDs.isEmpty {
            activeID = nil
        } else {
            // next neighbor if it exists at the same index, else the previous (now-last)
            activeID = tabIDs[min(idx, tabIDs.count - 1)]
        }
    }

    public mutating func move(from: Int, to: Int) {
        guard tabIDs.indices.contains(from), to >= 0, to <= tabIDs.count else { return }
        let id = tabIDs.remove(at: from)
        tabIDs.insert(id, at: min(to, tabIDs.count))
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter TabsStateTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Run the full Core suite**

Run: `swift test`
Expected: PASS (all tests across URLResolver/BookmarkStore/HistoryStore/TabsState + Smoke).

- [ ] **Step 6: Commit**

```bash
git add Sources/MiniBrowserCore/TabsState.swift Tests/MiniBrowserCoreTests/TabsStateTests.swift
git commit -m "feat: TabsState tab-collection state machine"
```

---

## Task 8: Single-tab browsing UI (M2)

Wires Core into a working one-page browser: address bar (resolve + autocomplete), back/forward/reload, and history recording. Uses one `Tab` instance for now; multi-tab is Task 9. UI is verified manually.

**Files:**
- Create: `Sources/MiniBrowserApp/Tab.swift`
- Modify: `Sources/MiniBrowserApp/WebView.swift` (replace `SmokeWebView` with a `Tab`-bound `WebView`)
- Create: `Sources/MiniBrowserApp/AddressBar.swift`
- Create: `Sources/MiniBrowserApp/BottomToolbar.swift`
- Create: `Sources/MiniBrowserApp/BrowserView.swift`
- Modify: `Sources/MiniBrowserApp/MiniBrowserApp.swift` (show `BrowserView`)

**Interfaces:**
- Consumes: `URLResolver`, `MobileUserAgent`, `HistoryStore`, `AppPaths`.
- Produces:
  - `final class Tab: ObservableObject, Identifiable` owning a `WKWebView` (G4), publishing `title/url/progress/canGoBack/canGoForward/isLoading/loadError`, with `func load(_ url: URL)`, `goBack()`, `goForward()`, `reload()`, `stop()`.
  - `struct WebView: NSViewRepresentable` bound to a `Tab` plus an `onCommit: (URL, String) -> Void` history callback.
  - `AddressBar`, `BottomToolbar`, `BrowserView`.

- [ ] **Step 1: Create `Tab.swift` (G4 — owns the web view, KVO → @Published)**

```swift
import Foundation
import WebKit
import Combine
import MiniBrowserCore

final class Tab: ObservableObject, Identifiable {
    let id = UUID()
    let webView: WKWebView

    @Published var title: String = ""
    @Published var url: URL?
    @Published var progress: Double = 0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var loadError: String?

    private var kvo: [NSKeyValueObservation] = []

    init(configuration: WKWebViewConfiguration = WKWebViewConfiguration()) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = MobileUserAgent.iPhoneSafari   // G3: before any load
        observe()
    }

    private func observe() {
        // KVO for continuous/derived state -> @Published (main thread).
        kvo = [
            webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
                self?.title = wv.title ?? ""
            },
            webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
                self?.url = wv.url
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                self?.progress = wv.estimatedProgress
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
                self?.canGoBack = wv.canGoBack
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in
                self?.canGoForward = wv.canGoForward
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
                self?.isLoading = wv.isLoading
            },
        ]
    }

    func load(_ url: URL) {
        loadError = nil
        webView.load(URLRequest(url: url))
    }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { loadError = nil; webView.reload() }
    func stop() { webView.stopLoading() }

    deinit { kvo.forEach { $0.invalidate() } }   // G4: prevent crashes/leaks
}
```

- [ ] **Step 2: Replace `WebView.swift` with the `Tab`-bound representable**

```swift
import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    @ObservedObject var tab: Tab
    /// Called when a navigation finishes, for history recording: (url, title).
    var onCommit: (URL, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCommit: onCommit) }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(tab.webView, to: container, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.onCommit = onCommit
        if container.subviews.first !== tab.webView {
            container.subviews.forEach { $0.removeFromSuperview() }
            attach(tab.webView, to: container, coordinator: context.coordinator)
        }
    }

    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        container.subviews.forEach { $0.removeFromSuperview() }   // detach, never dealloc
    }

    private func attach(_ webView: WKWebView, to container: NSView, coordinator: Coordinator) {
        webView.navigationDelegate = coordinator
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onCommit: (URL, String) -> Void
        init(onCommit: @escaping (URL, String) -> Void) { self.onCommit = onCommit }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let url = webView.url {
                onCommit(url, webView.title ?? "")
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error, on: webView)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error, on: webView)
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            FileHandle.standardError.write(Data("WebContent process terminated — reloading (G2)\n".utf8))
            webView.reload()
        }
        private func report(_ error: Error, on webView: WKWebView) {
            FileHandle.standardError.write(Data("nav failed: \(error)\n".utf8))
        }
    }
}
```

- [ ] **Step 3: Create `AddressBar.swift`**

```swift
import SwiftUI
import MiniBrowserCore

struct AddressBar: View {
    @ObservedObject var tab: Tab
    let historyStore: HistoryStore
    let onSubmit: (URL) -> Void

    @State private var text: String = ""
    @State private var editing = false
    @State private var suggestions: [HistoryEntry] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TextField("검색 또는 주소 입력", text: $text, onEditingChanged: { editing = $0 })
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
                    .onChange(of: text) { _, newValue in
                        suggestions = historyStore.suggestions(for: newValue, limit: 6)
                    }
                if tab.isLoading {
                    Button(action: tab.stop) { Image(systemName: "xmark") }
                } else {
                    Button(action: tab.reload) { Image(systemName: "arrow.clockwise") }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            if tab.isLoading {
                ProgressView(value: tab.progress).progressViewStyle(.linear)
            }

            if editing && !suggestions.isEmpty {
                ForEach(suggestions) { entry in
                    Button {
                        onSubmit(entry.url)
                        text = entry.url.absoluteString
                        suggestions = []
                    } label: {
                        HStack {
                            Text(entry.title.isEmpty ? entry.url.absoluteString : entry.title)
                                .lineLimit(1)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                }
            }
        }
        .onChange(of: tab.url) { _, newURL in
            if !editing { text = newURL?.absoluteString ?? "" }
        }
    }

    private func submit() {
        guard let url = URLResolver.resolve(text) else { return }
        onSubmit(url)
        suggestions = []
    }
}
```

- [ ] **Step 4: Create `BottomToolbar.swift`**

```swift
import SwiftUI

struct BottomToolbar: View {
    @ObservedObject var tab: Tab

    var body: some View {
        HStack {
            Button(action: tab.goBack) { Image(systemName: "chevron.left") }
                .disabled(!tab.canGoBack)
            Spacer()
            Button(action: tab.goForward) { Image(systemName: "chevron.right") }
                .disabled(!tab.canGoForward)
            Spacer()
            Button(action: tab.reload) { Image(systemName: "arrow.clockwise") }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}
```

- [ ] **Step 5: Create `BrowserView.swift` (single tab for now)**

```swift
import SwiftUI
import MiniBrowserCore

struct BrowserView: View {
    @StateObject private var tab = Tab()
    private let historyStore = HistoryStore(directory: AppPaths.supportDirectory())

    var body: some View {
        VStack(spacing: 0) {
            AddressBar(tab: tab, historyStore: historyStore, onSubmit: { tab.load($0) })
            Divider()
            ZStack {
                WebView(tab: tab) { url, title in
                    historyStore.record(url: url, title: title)
                }
                if let error = tab.loadError {
                    VStack(spacing: 12) {
                        Text("페이지를 열 수 없습니다").font(.headline)
                        Text(error).font(.caption).foregroundStyle(.secondary)
                        Button("재시도", action: tab.reload)
                    }
                    .padding()
                    .background(.background)
                }
            }
            Divider()
            BottomToolbar(tab: tab)
        }
        .onAppear {
            if tab.url == nil { tab.load(URL(string: "https://www.google.com")!) }
        }
    }
}
```

- [ ] **Step 6: Update `MiniBrowserApp.swift` to show `BrowserView`**

Replace the `WindowGroup` body (keep the `init()` activation bootstrap from Task 2 unchanged):
```swift
    var body: some Scene {
        WindowGroup {
            BrowserView()
                .frame(width: 390, height: 844)
        }
        .windowResizability(.contentSize)
    }
```
Also delete the now-unused `SmokeView` struct from `MiniBrowserApp.swift`.

- [ ] **Step 7: Build, test, and verify manually**

Run: `swift build`
Expected: builds with no errors.

Run: `swift test`
Expected: all Core tests still PASS.

Run: `./scripts/run.sh`
Expected — confirm:
1. Google opens in mobile layout.
2. Typing a domain (e.g. `apple.com`) + Enter navigates to `https://apple.com`.
3. Typing a phrase (e.g. `swift programming`) + Enter runs a Google search.
4. Back/forward/reload work and enable/disable correctly.
5. After visiting a few pages, typing part of one shows it as a suggestion.

- [ ] **Step 8: Commit**

```bash
git add Sources/MiniBrowserApp
git commit -m "feat: single-tab browsing UI (address bar, toolbar, history)"
```

---

## Task 9: Tabs (M3, G4)

Introduces `TabsModel` (backed by Core's `TabsState`), a tab switcher, and `target=_blank`/`window.open` → new tab. Each tab keeps its own live web view (G4).

**Files:**
- Create: `Sources/MiniBrowserApp/TabsModel.swift`
- Modify: `Sources/MiniBrowserApp/WebView.swift` (add `WKUIDelegate` `createWebViewWith`; bind active tab via model)
- Create: `Sources/MiniBrowserApp/TabSwitcherView.swift`
- Modify: `Sources/MiniBrowserApp/BrowserView.swift` (drive the active tab from `TabsModel`; add tab button)
- Modify: `Sources/MiniBrowserApp/BottomToolbar.swift` (add tabs button with count)

**Interfaces:**
- Consumes: `TabsState`, `Tab`, `HistoryStore`.
- Produces:
  - `final class TabsModel: ObservableObject` with `@Published var tabs: [Tab]`, `var activeID: UUID?` (mirrors `TabsState`), `var active: Tab?`, `@discardableResult func newTab(configuration:url:) -> Tab`, `func close(_ id: UUID)`, `func select(_ id: UUID)`.
  - `WebView` gains `model: TabsModel` so `createWebViewWith` can append a tab.
  - `TabSwitcherView`.

- [ ] **Step 1: Create `TabsModel.swift`**

```swift
import Foundation
import WebKit
import Combine
import MiniBrowserCore

final class TabsModel: ObservableObject {
    @Published private(set) var tabs: [Tab] = []
    @Published private(set) var activeID: UUID?

    private var state = TabsState()

    var active: Tab? { tabs.first { $0.id == activeID } }

    private func sync() {
        // Keep tabs[] ordered to match state.tabIDs, and publish activeID.
        let byID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        tabs = state.tabIDs.compactMap { byID[$0] }
        activeID = state.activeID
    }

    @discardableResult
    func newTab(configuration: WKWebViewConfiguration = WKWebViewConfiguration(), url: URL? = nil) -> Tab {
        let tab = Tab(configuration: configuration)
        tabs.append(tab)             // add the instance before state.sync reorders
        state.add(tab.id)
        sync()
        if let url { tab.load(url) }
        return tab
    }

    func close(_ id: UUID) {
        state.close(id)
        tabs.removeAll { $0.id == id }
        sync()
        if tabs.isEmpty { newTab(url: URL(string: "https://www.google.com")!) }
    }

    func select(_ id: UUID) {
        state.select(id)
        sync()
    }
}
```

- [ ] **Step 2: Extend `WebView.swift` for new-tab handling (WKUIDelegate)**

Add `var model: TabsModel` to the `WebView` struct, set the uiDelegate in `attach`, pass the model into the Coordinator, and implement `createWebViewWith`.

Change the struct header and `makeCoordinator`:
```swift
struct WebView: NSViewRepresentable {
    @ObservedObject var tab: Tab
    let model: TabsModel
    var onCommit: (URL, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(model: model, onCommit: onCommit) }
```

In `attach(...)`, also set the UI delegate:
```swift
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
```

Update the `Coordinator` to hold the model weakly and handle `createWebViewWith`:
```swift
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var model: TabsModel?
        var onCommit: (URL, String) -> Void
        init(model: TabsModel, onCommit: @escaping (URL, String) -> Void) {
            self.model = model
            self.onCommit = onCommit
        }

        // target=_blank / window.open -> new tab. Reuse the PASSED config; return its web view.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard let model else { return nil }
            let tab = model.newTab(configuration: configuration)
            return tab.webView   // WebKit drives the load; preserves window.opener
        }

        // ... keep didFinish / didFail / didFailProvisionalNavigation / webViewWebContentProcessDidTerminate
        //     exactly as in Task 8 ...
    }
```
Also update the `Coordinator(...)` call site in `updateNSView` is unaffected (it only refreshes `onCommit`); add `context.coordinator.model = model` at the top of `updateNSView` so it stays current:
```swift
    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.model = model
        context.coordinator.onCommit = onCommit
        if container.subviews.first !== tab.webView {
            container.subviews.forEach { $0.removeFromSuperview() }
            attach(tab.webView, to: container, coordinator: context.coordinator)
        }
    }
```

- [ ] **Step 3: Create `TabSwitcherView.swift`**

```swift
import SwiftUI

struct TabSwitcherView: View {
    @ObservedObject var model: TabsModel
    @Binding var isPresented: Bool

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("새 탭") {
                    model.newTab(url: URL(string: "https://www.google.com")!)
                    isPresented = false
                }
                Spacer()
                Button("완료") { isPresented = false }
            }
            .padding(12)
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.tabs) { tab in
                        TabCard(tab: tab,
                                isActive: tab.id == model.activeID,
                                onSelect: { model.select(tab.id); isPresented = false },
                                onClose: { model.close(tab.id) })
                    }
                }
                .padding(12)
            }
        }
    }
}

private struct TabCard: View {
    @ObservedObject var tab: Tab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tab.title.isEmpty ? "새 탭" : tab.title).lineLimit(1).font(.caption.bold())
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
            Text(tab.url?.host() ?? "").lineLimit(1).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(height: 80, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(isActive ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
```

- [ ] **Step 4: Rewrite `BrowserView.swift` to drive the active tab from `TabsModel`**

```swift
import SwiftUI
import MiniBrowserCore

struct BrowserView: View {
    @StateObject private var model = TabsModel()
    @State private var showTabs = false
    private let historyStore = HistoryStore(directory: AppPaths.supportDirectory())

    var body: some View {
        Group {
            if showTabs {
                TabSwitcherView(model: model, isPresented: $showTabs)
            } else if let tab = model.active {
                VStack(spacing: 0) {
                    AddressBar(tab: tab, historyStore: historyStore, onSubmit: { tab.load($0) })
                    Divider()
                    ZStack {
                        WebView(tab: tab, model: model) { url, title in
                            historyStore.record(url: url, title: title)
                        }
                        if let error = tab.loadError {
                            VStack(spacing: 12) {
                                Text("페이지를 열 수 없습니다").font(.headline)
                                Text(error).font(.caption).foregroundStyle(.secondary)
                                Button("재시도", action: tab.reload)
                            }
                            .padding().background(.background)
                        }
                    }
                    Divider()
                    BottomToolbar(tab: tab, tabCount: model.tabs.count, onShowTabs: { showTabs = true })
                }
                .id(tab.id)   // rebind chrome when the active tab changes; web view persists in the model
            }
        }
        .onAppear {
            if model.tabs.isEmpty { model.newTab(url: URL(string: "https://www.google.com")!) }
        }
    }
}
```

- [ ] **Step 5: Extend `BottomToolbar.swift` with the tabs button**

```swift
import SwiftUI

struct BottomToolbar: View {
    @ObservedObject var tab: Tab
    let tabCount: Int
    let onShowTabs: () -> Void

    var body: some View {
        HStack {
            Button(action: tab.goBack) { Image(systemName: "chevron.left") }
                .disabled(!tab.canGoBack)
            Spacer()
            Button(action: tab.goForward) { Image(systemName: "chevron.right") }
                .disabled(!tab.canGoForward)
            Spacer()
            Button(action: tab.reload) { Image(systemName: "arrow.clockwise") }
            Spacer()
            Button(action: onShowTabs) {
                Label("\(tabCount)", systemImage: "square.on.square")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}
```

- [ ] **Step 6: Build, test, verify manually**

Run: `swift build` — Expected: no errors.
Run: `swift test` — Expected: all Core tests PASS.
Run: `./scripts/run.sh` — confirm:
1. Tabs button shows the count; tapping opens the switcher.
2. "새 탭" creates a tab; selecting a card switches to it **with its page/scroll preserved** (G4).
3. Closing the active tab selects a neighbor; closing the last tab opens a fresh start tab.
4. A link that opens in a new tab (`target=_blank`) creates a new tab.

- [ ] **Step 7: Commit**

```bash
git add Sources/MiniBrowserApp
git commit -m "feat: tabs — TabsModel, switcher, target=_blank new tabs (G4)"
```

---

## Task 10: Bookmarks + Start page (M4)

Adds bookmark add/open and a start page (favorites grid + recent history) shown for blank tabs.

**Files:**
- Create: `Sources/MiniBrowserApp/StartPageView.swift`
- Modify: `Sources/MiniBrowserApp/TabsModel.swift` (allow tabs with no initial URL = start page)
- Modify: `Sources/MiniBrowserApp/BottomToolbar.swift` (add bookmark button)
- Modify: `Sources/MiniBrowserApp/BrowserView.swift` (show start page when active tab has no url; pass stores)

**Interfaces:**
- Consumes: `BookmarkStore`, `HistoryStore`, `Bookmark`, `Tab`, `TabsModel`.
- Produces: `StartPageView`. `BrowserView` owns a shared `BookmarkStore`.

- [ ] **Step 1: Create `StartPageView.swift`**

```swift
import SwiftUI
import MiniBrowserCore

struct StartPageView: View {
    let bookmarks: [Bookmark]
    let recent: [HistoryEntry]
    let onOpen: (URL) -> Void

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !bookmarks.isEmpty {
                    Text("즐겨찾기").font(.headline).padding(.horizontal)
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(bookmarks) { b in
                            Button { onOpen(b.url) } label: {
                                VStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(.quaternary)
                                        .frame(width: 56, height: 56)
                                        .overlay(Text(initials(b.title)).font(.title3.bold()))
                                    Text(b.title).font(.caption2).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }

                if !recent.isEmpty {
                    Text("최근 방문").font(.headline).padding(.horizontal)
                    VStack(spacing: 0) {
                        ForEach(recent) { entry in
                            Button { onOpen(entry.url) } label: {
                                HStack {
                                    Text(entry.title.isEmpty ? entry.url.absoluteString : entry.title)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 8).padding(.horizontal)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
            .padding(.vertical)
        }
    }

    private func initials(_ s: String) -> String {
        String(s.prefix(1)).uppercased()
    }
}
```

- [ ] **Step 2: Allow start-page tabs in `TabsModel.swift`**

`newTab(url:)` already accepts `url: URL? = nil` (no load when nil → start page). Change the "new tab" entry points to open the start page instead of Google. In `close(_:)` replace the auto-created tab and in `TabSwitcherView` "새 탭", create a start-page tab:

In `TabsModel.close(_:)`:
```swift
        if tabs.isEmpty { newTab() }   // start page (no URL)
```

In `TabSwitcherView` "새 탭" button:
```swift
                Button("새 탭") {
                    model.newTab()      // start page
                    isPresented = false
                }
```

In `BrowserView.onAppear`:
```swift
            if model.tabs.isEmpty { model.newTab() }   // start page
```

- [ ] **Step 3: Add a bookmark button to `BottomToolbar.swift`**

Add two parameters and a button:
```swift
struct BottomToolbar: View {
    @ObservedObject var tab: Tab
    let tabCount: Int
    let isBookmarked: Bool
    let onToggleBookmark: () -> Void
    let onShowTabs: () -> Void

    var body: some View {
        HStack {
            Button(action: tab.goBack) { Image(systemName: "chevron.left") }
                .disabled(!tab.canGoBack)
            Spacer()
            Button(action: tab.goForward) { Image(systemName: "chevron.right") }
                .disabled(!tab.canGoForward)
            Spacer()
            Button(action: onToggleBookmark) {
                Image(systemName: isBookmarked ? "star.fill" : "star")
            }
            .disabled(tab.url == nil)
            Spacer()
            Button(action: onShowTabs) {
                Label("\(tabCount)", systemImage: "square.on.square")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}
```

- [ ] **Step 4: Wire bookmarks + start page into `BrowserView.swift`**

```swift
import SwiftUI
import MiniBrowserCore

struct BrowserView: View {
    @StateObject private var model = TabsModel()
    @State private var showTabs = false
    @State private var bookmarkTick = 0   // bump to refresh bookmark-derived views
    private let historyStore = HistoryStore(directory: AppPaths.supportDirectory())
    private let bookmarkStore = BookmarkStore(directory: AppPaths.supportDirectory())

    var body: some View {
        Group {
            if showTabs {
                TabSwitcherView(model: model, isPresented: $showTabs)
            } else if let tab = model.active {
                VStack(spacing: 0) {
                    AddressBar(tab: tab, historyStore: historyStore, onSubmit: { tab.load($0) })
                    Divider()
                    ZStack {
                        if tab.url == nil {
                            StartPageView(
                                bookmarks: bookmarkStore.all(),
                                recent: historyStore.recent(limit: 12),
                                onOpen: { tab.load($0) }
                            )
                            .id(bookmarkTick)
                        } else {
                            WebView(tab: tab, model: model) { url, title in
                                historyStore.record(url: url, title: title)
                            }
                        }
                        if let error = tab.loadError {
                            VStack(spacing: 12) {
                                Text("페이지를 열 수 없습니다").font(.headline)
                                Text(error).font(.caption).foregroundStyle(.secondary)
                                Button("재시도", action: tab.reload)
                            }
                            .padding().background(.background)
                        }
                    }
                    Divider()
                    BottomToolbar(
                        tab: tab,
                        tabCount: model.tabs.count,
                        isBookmarked: isBookmarked(tab.url),
                        onToggleBookmark: { toggleBookmark(tab) },
                        onShowTabs: { showTabs = true }
                    )
                }
                .id(tab.id)
            }
        }
        .onAppear {
            if model.tabs.isEmpty { model.newTab() }
        }
    }

    private func isBookmarked(_ url: URL?) -> Bool {
        guard let url else { return false }
        return bookmarkStore.all().contains { $0.url == url }
    }

    private func toggleBookmark(_ tab: Tab) {
        guard let url = tab.url else { return }
        if let existing = bookmarkStore.all().first(where: { $0.url == url }) {
            bookmarkStore.remove(id: existing.id)
        } else {
            bookmarkStore.add(Bookmark(title: tab.title.isEmpty ? url.absoluteString : tab.title, url: url))
        }
        bookmarkTick += 1
    }
}
```

- [ ] **Step 5: Build, test, verify manually**

Run: `swift build` — Expected: no errors.
Run: `swift test` — Expected: all Core tests PASS.
Run: `./scripts/run.sh` — confirm:
1. A new tab shows the start page (favorites + recent).
2. Star button bookmarks the current page; tapping again removes it; the icon reflects state.
3. Bookmarked sites appear on the start page and open when tapped.
4. Recent history appears on the start page and opens when tapped.

- [ ] **Step 6: Commit**

```bash
git add Sources/MiniBrowserApp
git commit -m "feat: bookmarks + start page (favorites grid, recent history)"
```

---

## Self-Review (completed by plan author)

**1. Spec coverage:**
- §1 scope (core, tabs, bookmarks, history; passwords excluded) → Tasks 3/5/6/7 (Core) + 8/9/10 (UI). Passwords intentionally absent. ✓
- §2 G1 activation → Task 2 Step 1 + Global Constraints. ✓
- §2 G2 `.app` bundle → Task 1 Step 4 (`run.sh`), verified Task 2 Step 4. ✓
- §2 G3 mobile UA + width → `MobileUserAgent` (Task 3), set in `Tab` (Task 8), 390pt frame (Tasks 2/8). ✓
- §2 G4 per-tab persistence → `Tab` owns web view (Task 8), swap-not-recreate `WebView` (Task 8/9), KVO invalidate in deinit (Task 8). ✓
- §4.1 URLResolver → Task 3. §4.2 SearchEngine → Task 3. §4.3 BookmarkStore → Task 5. §4.4 HistoryStore → Task 6. §4.5 TabsState → Task 7. §4.6 Tab → Task 8. §4.7 TabsModel → Task 9. §4.8 WebView → Tasks 8/9. §4.9 Views → Tasks 8/9/10. ✓
- §5 data flow, §6 error handling (loadError UI + WebContent reload), §7 persistence (AppPaths + stores), §8 build (run.sh), §9 tests (Core suites + manual smoke). ✓
- §11 milestones M0–M4 → Tasks 2 / 3–7 / 8 / 9 / 10. ✓

**2. Placeholder scan:** No "TBD/TODO/handle edge cases" left; every code step shows complete code. The one temporary `Placeholder.swift` (Task 1) is explicitly created and deleted in Task 3. ✓

**3. Type consistency:** `Tab` published names (`title/url/progress/canGoBack/canGoForward/isLoading/loadError`) used identically in `AddressBar`/`BottomToolbar`/`TabSwitcherView`. `TabsModel` API (`tabs/activeID/active/newTab/close/select`) consistent across `WebView`/`BrowserView`/`TabSwitcherView`. `URLResolver.resolve`, `HistoryStore.record/recent/suggestions`, `BookmarkStore.all/add/remove/move` signatures match between definition and call sites. `BottomToolbar` evolves across Tasks 8→9→10; each modifying task restates its full signature and the matching `BrowserView` call site. ✓
