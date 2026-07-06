# 전역 색반전 + 설정 저장 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Color inversion becomes one app-wide switch (applies to all tabs, new tabs, and survives restarts), and the ad-block / boss-mode toggles persist too, all in `settings.json`.

**Architecture:** A lenient-decoding `Settings` struct + `SettingsStore` in MiniBrowserCore (TDD) persists to `settings.json` alongside the other JSON stores. An `@MainActor` `AppSettings` singleton in the app loads it once, saves on every change, and propagates inversion changes to all tabs via a callback registered by `TabsModel`. `Tab` keeps its CSS-injection mechanics but is driven by the global value; `AdBlocker`/`BossMode` initialize from and mirror back to `AppSettings`.

**Tech Stack:** Swift 6.3 Swift Package, SwiftUI + WKWebView, XCTest. No new dependencies.

**Design spec:** `docs/superpowers/specs/2026-07-06-global-invert-settings-design.md`

## Global Constraints

- Defaults (missing/corrupt/absent file): `inverted=false, adBlockEnabled=true, bossModeEnabled=true` — identical to today's launch behavior.
- Field-wise lenient decoding (`decodeIfPresent ?? default`, the `TabSnapshot` pattern) so old/partial files never fail.
- One-time migration: when `settings.json` did NOT exist at launch, the session's **active tab** inversion becomes the initial global value.
- `session.json` format unchanged; `TabSnapshot.inverted` keeps being written (with the global value) for backward compatibility.
- Settings save immediately on change (no debounce).
- Zoom stays per-tab (out of scope).
- Code comments in English; user-visible strings Korean.
- Build/tests: `swift build && swift test` from /Users/seojeonghwa/project/miniBrowser. Currently 82 tests; Task 1 adds 7 (expect **89**). Never run the app via bare `swift run` — use `./scripts/run.sh`.
- Commit messages: conventional-commit style ending with the trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: `Settings` + `SettingsStore` (MiniBrowserCore, TDD)

**Files:**
- Create: `Sources/MiniBrowserCore/SettingsStore.swift`
- Test: `Tests/MiniBrowserCoreTests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: nothing (pure Foundation).
- Produces (used by Task 2):
  ```swift
  public struct Settings: Codable, Equatable {
      public var inverted: Bool
      public var adBlockEnabled: Bool
      public var bossModeEnabled: Bool
      public init(inverted: Bool = false, adBlockEnabled: Bool = true, bossModeEnabled: Bool = true)
  }
  public final class SettingsStore {
      public init(directory: URL)
      public var fileExists: Bool
      public func load() -> Settings   // missing/corrupt -> Settings()
      public func save(_ settings: Settings)
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/MiniBrowserCoreTests/SettingsStoreTests.swift
import XCTest
@testable import MiniBrowserCore

final class SettingsStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testDefaultsMatchCurrentLaunchBehavior() {
        let s = Settings()
        XCTAssertFalse(s.inverted)
        XCTAssertTrue(s.adBlockEnabled)
        XCTAssertTrue(s.bossModeEnabled)
    }

    func testRoundTrip() {
        let dir = tempDir()
        let s = Settings(inverted: true, adBlockEnabled: false, bossModeEnabled: false)
        SettingsStore(directory: dir).save(s)
        XCTAssertEqual(SettingsStore(directory: dir).load(), s)
    }

    func testLoadMissingReturnsDefaults() {
        XCTAssertEqual(SettingsStore(directory: tempDir()).load(), Settings())
    }

    func testCorruptFileReturnsDefaults() throws {
        let dir = tempDir()
        try Data("not json at all".utf8).write(to: dir.appendingPathComponent("settings.json"))
        XCTAssertEqual(SettingsStore(directory: dir).load(), Settings())
    }

    func testOlderFileWithMissingFieldsGetsDefaults() throws {
        let dir = tempDir()
        try Data(#"{"inverted":true}"#.utf8).write(to: dir.appendingPathComponent("settings.json"))
        let s = SettingsStore(directory: dir).load()
        XCTAssertTrue(s.inverted)                 // present field honored
        XCTAssertTrue(s.adBlockEnabled)           // missing fields -> defaults
        XCTAssertTrue(s.bossModeEnabled)
    }

    func testUnknownFieldsIgnored() throws {
        let dir = tempDir()
        try Data(#"{"inverted":true,"futureSetting":123}"#.utf8).write(to: dir.appendingPathComponent("settings.json"))
        XCTAssertTrue(SettingsStore(directory: dir).load().inverted)
    }

    func testFileExists() {
        let dir = tempDir()
        let store = SettingsStore(directory: dir)
        XCTAssertFalse(store.fileExists)
        store.save(Settings())
        XCTAssertTrue(store.fileExists)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SettingsStoreTests`
Expected: compile FAILURE — `cannot find 'Settings' in scope`

- [ ] **Step 3: Write the implementation**

```swift
// Sources/MiniBrowserCore/SettingsStore.swift
import Foundation

/// App-wide user settings. Fields decode leniently (missing -> default) so files
/// written by older versions keep working as settings are added over time.
public struct Settings: Codable, Equatable {
    public var inverted: Bool          // global color inversion (dark-mode-ish)
    public var adBlockEnabled: Bool
    public var bossModeEnabled: Bool   // shrink the window when idle (자리비움 자동 숨김)

    public init(inverted: Bool = false, adBlockEnabled: Bool = true, bossModeEnabled: Bool = true) {
        self.inverted = inverted
        self.adBlockEnabled = adBlockEnabled
        self.bossModeEnabled = bossModeEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inverted = try c.decodeIfPresent(Bool.self, forKey: .inverted) ?? false
        adBlockEnabled = try c.decodeIfPresent(Bool.self, forKey: .adBlockEnabled) ?? true
        bossModeEnabled = try c.decodeIfPresent(Bool.self, forKey: .bossModeEnabled) ?? true
    }
}

/// Loads/saves `Settings` as JSON (`settings.json`), like the other app stores.
public final class SettingsStore {
    private let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("settings.json")
    }

    /// Whether a settings file exists yet (used for one-time migrations).
    public var fileExists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    /// Missing or corrupt file -> defaults; the app must always be able to start.
    public func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    public func save(_ settings: Settings) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SettingsStoreTests`
Expected: `Executed 7 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add Sources/MiniBrowserCore/SettingsStore.swift Tests/MiniBrowserCoreTests/SettingsStoreTests.swift
git commit -m "feat(core): Settings + SettingsStore — lenient persisted app settings"
```

---

### Task 2: `AppSettings` + app wiring (global invert, persisted toggles)

**Files:**
- Create: `Sources/MiniBrowserApp/AppSettings.swift`
- Modify: `Sources/MiniBrowserApp/Tab.swift`
- Modify: `Sources/MiniBrowserApp/TabsModel.swift`
- Modify: `Sources/MiniBrowserApp/BottomToolbar.swift`
- Modify: `Sources/MiniBrowserApp/AdBlocker.swift`
- Modify: `Sources/MiniBrowserApp/BossMode.swift`

**Interfaces:**
- Consumes: `Settings`/`SettingsStore` (Task 1), `AppPaths.supportDirectory()` (exists).
- Produces:
  ```swift
  @MainActor final class AppSettings: ObservableObject {
      static let shared: AppSettings
      let loadedFromDisk: Bool
      var onInvertedChange: ((Bool) -> Void)?
      @Published var inverted: Bool          // didSet: save + onInvertedChange
      @Published var adBlockEnabled: Bool    // didSet: save
      @Published var bossModeEnabled: Bool   // didSet: save
      func migrateInvertedIfNeeded(fromSession sessionInverted: Bool)
  }
  // Tab: func setInverted(_ on: Bool)   (replaces toggleInvert)
  // Tab: func applyRestored(zoom: Double)   (drops the inverted parameter)
  ```

- [ ] **Step 1: Create `AppSettings`**

```swift
// Sources/MiniBrowserApp/AppSettings.swift
import Foundation
import MiniBrowserCore

/// App-wide persisted settings: global color inversion, ad blocking, boss mode.
/// Loads once from settings.json at launch and saves immediately on every change.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// True when settings.json existed at launch — gates the one-time migration
    /// that inherits the old per-tab inversion from the session.
    let loadedFromDisk: Bool

    /// Registered by TabsModel so a global inversion change reaches every tab.
    var onInvertedChange: ((Bool) -> Void)?

    @Published var inverted: Bool {
        didSet {
            guard oldValue != inverted else { return }
            save()
            onInvertedChange?(inverted)
        }
    }
    @Published var adBlockEnabled: Bool {
        didSet { if oldValue != adBlockEnabled { save() } }
    }
    @Published var bossModeEnabled: Bool {
        didSet { if oldValue != bossModeEnabled { save() } }
    }

    private let store = SettingsStore(directory: AppPaths.supportDirectory())

    private init() {
        loadedFromDisk = store.fileExists
        let s = store.load()
        inverted = s.inverted
        adBlockEnabled = s.adBlockEnabled
        bossModeEnabled = s.bossModeEnabled
    }

    /// First run without a settings file: inherit the session's inversion so the
    /// user's existing tabs keep looking the same after the per-tab -> global switch.
    func migrateInvertedIfNeeded(fromSession sessionInverted: Bool) {
        guard !loadedFromDisk else { return }
        inverted = sessionInverted   // didSet persists + propagates (no-op if equal)
    }

    private func save() {
        store.save(Settings(inverted: inverted,
                            adBlockEnabled: adBlockEnabled,
                            bossModeEnabled: bossModeEnabled))
    }
}
```

Note: `store` is used inside `init` before all stored properties are set — Swift allows `let store = SettingsStore(...)` as a property initializer, which runs first; if the compiler objects to `AppPaths.supportDirectory()` in a property initializer under strict concurrency, move the assignment to the first line of `init()` (`store = SettingsStore(directory: AppPaths.supportDirectory())` with `private let store: SettingsStore`).

- [ ] **Step 2: Drive `Tab` inversion from the global**

In `Sources/MiniBrowserApp/Tab.swift`:

(a) In `init`, after the two `register` lines (`ElementHider.shared.register(webView)`), add:

```swift
        inverted = AppSettings.shared.inverted   // global setting drives inversion
        if inverted { installInvertScript() }
```

(b) Replace `applyRestored(zoom:inverted:)`:

```swift
    /// Restore persisted per-tab state (zoom). Inversion is a global setting now;
    /// the URL is set separately as `pendingURL` and loaded on first activation.
    func applyRestored(zoom: Double) {
        self.zoom = zoom
        webView.pageZoom = zoom
    }
```

(c) Replace `toggleInvert()`:

```swift
    /// Apply the app-wide inversion setting to this tab (no-op when unchanged).
    func setInverted(_ on: Bool) {
        guard inverted != on else { return }
        inverted = on
        installInvertScript()   // applies to every future load, from the first paint
        applyInvert()           // and to the page already on screen
    }
```

- [ ] **Step 3: Wire `TabsModel` — propagation callback, migration, persist**

In `Sources/MiniBrowserApp/TabsModel.swift`:

(a) At the end of `init()` (after the `NotificationCenter` observer), add:

```swift
        // A global inversion change applies to every live tab immediately.
        AppSettings.shared.onInvertedChange = { [weak self] on in
            self?.tabs.forEach { $0.setInverted(on) }
        }
```

(b) In `restore()`, right after the `guard let session … else { newTab(); return }` line, add:

```swift
        // One-time migration (no settings.json yet): the previous per-tab
        // inversion of the active tab becomes the initial global value.
        let activeIdx = session.activeIndex ?? 0
        let sessionInverted = session.tabs.indices.contains(activeIdx)
            ? session.tabs[activeIdx].inverted : false
        AppSettings.shared.migrateInvertedIfNeeded(fromSession: sessionInverted)
```

(c) In the same `restore()` loop, change `tab.applyRestored(zoom: snap.zoom, inverted: snap.inverted)` to:

```swift
            tab.applyRestored(zoom: snap.zoom)
```

(d) In `persist()`, change the snapshot line to write the global value (backward-compatible format):

```swift
        let snaps = tabs.map {
            TabSnapshot(url: $0.url ?? $0.pendingURL, title: $0.title, zoom: $0.zoom,
                        inverted: AppSettings.shared.inverted)
        }
```

- [ ] **Step 4: `BottomToolbar` — global invert toggle**

In `Sources/MiniBrowserApp/BottomToolbar.swift`:

(a) Add an observed object below `@ObservedObject private var hider = ElementHider.shared`:

```swift
    @ObservedObject private var settings = AppSettings.shared
```

(b) Replace the invert button (including its `.disabled` modifier — the global toggle works even on the start page):

```swift
                Button { settings.inverted.toggle() } label: {
                    Label(settings.inverted ? "색 반전 끄기" : "색 반전 (전체)",
                          systemImage: "circle.righthalf.filled")
                }
```

(The ad-block and boss-mode buttons stay as they are — persistence is wired inside those classes in Steps 5–6.)

- [ ] **Step 5: `AdBlocker` — initialize from and mirror to settings**

In `Sources/MiniBrowserApp/AdBlocker.swift`, replace the `enabled` property and `init`:

```swift
    @Published var enabled = true {
        didSet {
            applyAll()
            AppSettings.shared.adBlockEnabled = enabled   // persist (no-op if unchanged)
        }
    }
```

```swift
    private init() {
        enabled = AppSettings.shared.adBlockEnabled   // fires didSet: applyAll on empty set is harmless
        compile()
    }
```

- [ ] **Step 6: `BossMode` — initialize from and mirror to settings**

In `Sources/MiniBrowserApp/BossMode.swift`:

(a) Replace the `enabled` property:

```swift
    @Published var enabled = true {
        didSet {
            if !enabled { restore() }
            idleSince = Date()
            AppSettings.shared.bossModeEnabled = enabled   // persist (no-op if unchanged)
        }
    }
```

(b) Add an initializer (the class currently has none) after the property declarations:

```swift
    init() {
        enabled = AppSettings.shared.bossModeEnabled
    }
```

- [ ] **Step 7: Build and full test run**

Run: `swift build && swift test`
Expected: clean build; **89 tests, 0 failures**.

- [ ] **Step 8: Commit**

```bash
git add Sources/MiniBrowserApp/AppSettings.swift Sources/MiniBrowserApp/Tab.swift \
        Sources/MiniBrowserApp/TabsModel.swift Sources/MiniBrowserApp/BottomToolbar.swift \
        Sources/MiniBrowserApp/AdBlocker.swift Sources/MiniBrowserApp/BossMode.swift
git commit -m "feat: global color inversion + persisted settings (adblock, boss mode)"
```

---

### Task 3: E2E verification, release

**Files:** none (verification; fix-forward commits if issues found).

- [ ] **Step 1:** `swift test` — 89/89.
- [ ] **Step 2:** Manual E2E via `./scripts/run.sh` (controller runs; protect the user's `session.json` with the usual backup/restore protocol):
  1. Migration: delete `settings.json`, session with inverted tabs → launch → pages render inverted, `settings.json` created with `"inverted":true`.
  2. Global toggle: Aa → 색 반전 끄기 → all open tabs un-invert immediately; new tab starts un-inverted; toggle on → all invert.
  3. Restart persistence: toggle invert off + 광고 차단 off + 자리비움 off → quit → relaunch → all three states preserved (`settings.json` reflects them).
  4. Regression: per-tab zoom still restores; back/forward stack + book-flip unaffected; session.json still carries `inverted` field.
- [ ] **Step 3:** Push, release v1.2.0 (`./scripts/release.sh 1.2.0 --publish`), commit cask, sync tap `Casks/minibrowser.rb`, `brew upgrade`, relaunch user app with their session.

---

## Self-Review Notes

- **Spec coverage:** Settings/SettingsStore + lenient decode + defaults (Task 1); global switch semantics, Tab mechanics reuse, propagation callback, migration from active tab, session format compat, adblock/boss persistence (Task 2); manual verification list mirrors the spec's (Task 3).
- **Type consistency:** `setInverted(_:)`, `applyRestored(zoom:)`, `migrateInvertedIfNeeded(fromSession:)`, `onInvertedChange` used identically across tasks.
- **Known interactions:** `AppSettings.inverted.didSet` → `onInvertedChange` → `tabs.forEach setInverted` — no feedback loop (Tab doesn't write back). AdBlocker/BossMode mirror-writes are no-ops when unchanged, so no save storms. Stacked live pages get the current inversion re-applied on reveal by the existing `show()` path.
