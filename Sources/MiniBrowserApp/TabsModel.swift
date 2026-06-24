import Foundation
import AppKit
import WebKit
import Combine
import MiniBrowserCore

@MainActor
final class TabsModel: ObservableObject {
    @Published private(set) var tabs: [Tab] = []
    @Published private(set) var activeID: UUID?

    private var state = TabsState()

    /// Canonical store of Tab instances, keyed by id. `sync()` is the sole writer of `tabs[]`,
    /// which it rebuilds from `state.tabIDs` using this registry — so there is no duplicate-key trap.
    private var tabsByID: [UUID: Tab] = [:]

    private let sessionStore = SessionStore(directory: AppPaths.supportDirectory())
    private var cancellables: [UUID: AnyCancellable] = [:]

    var active: Tab? { tabs.first { $0.id == activeID } }

    init() {
        // Flush the session on quit, in case a change is still inside the debounce window.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.persist() }
        }
    }

    private func sync() {
        // Keep tabs[] ordered to match state.tabIDs, and publish activeID.
        // This is the ONLY place that assigns `tabs`.
        tabs = state.tabIDs.compactMap { tabsByID[$0] }
        activeID = state.activeID
    }

    @discardableResult
    func newTab(configuration: WKWebViewConfiguration = WKWebViewConfiguration(), url: URL? = nil) -> Tab {
        let tab = Tab(configuration: configuration)
        register(tab)
        state.add(tab.id)
        sync()
        if let url { tab.load(url) }
        persist()
        return tab
    }

    func close(_ id: UUID) {
        state.close(id)
        tabsByID[id] = nil
        cancellables[id] = nil
        sync()
        if state.tabIDs.isEmpty { newTab() }   // start page (no URL); persists
        else { persist() }
    }

    func select(_ id: UUID) {
        state.select(id)
        sync()
        persist()
    }

    // MARK: - Session persistence

    /// Restore the previous session, or open a fresh start page if there's none.
    func restore() {
        guard let session = sessionStore.load(), !session.tabs.isEmpty else {
            newTab()
            return
        }
        for snap in session.tabs {
            let tab = Tab()
            tab.applyRestored(zoom: snap.zoom, inverted: snap.inverted)
            tab.pendingURL = snap.url
            register(tab)
            state.add(tab.id)
        }
        if let idx = session.activeIndex, state.tabIDs.indices.contains(idx) {
            state.select(state.tabIDs[idx])
        }
        sync()
    }

    private func register(_ tab: Tab) {
        tabsByID[tab.id] = tab
        // Persist (debounced) whenever a tab's URL, zoom, or inversion changes.
        cancellables[tab.id] = Publishers.Merge3(
            tab.$url.map { _ in () },
            tab.$zoom.map { _ in () },
            tab.$inverted.map { _ in () }
        )
        .debounce(for: .seconds(0.4), scheduler: RunLoop.main)
        .sink { [weak self] in self?.persist() }
    }

    private func persist() {
        let snaps = tabs.map {
            TabSnapshot(url: $0.url ?? $0.pendingURL, zoom: $0.zoom, inverted: $0.inverted)
        }
        let activeIndex = activeID.flatMap { id in tabs.firstIndex { $0.id == id } }
        sessionStore.save(Session(tabs: snaps, activeIndex: activeIndex))
    }
}
