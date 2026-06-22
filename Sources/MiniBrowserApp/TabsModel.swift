import Foundation
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

    var active: Tab? { tabs.first { $0.id == activeID } }

    private func sync() {
        // Keep tabs[] ordered to match state.tabIDs, and publish activeID.
        // This is the ONLY place that assigns `tabs`.
        tabs = state.tabIDs.compactMap { tabsByID[$0] }
        activeID = state.activeID
    }

    @discardableResult
    func newTab(configuration: WKWebViewConfiguration = WKWebViewConfiguration(), url: URL? = nil) -> Tab {
        let tab = Tab(configuration: configuration)
        tabsByID[tab.id] = tab
        state.add(tab.id)
        sync()
        if let url { tab.load(url) }
        return tab
    }

    func close(_ id: UUID) {
        state.close(id)
        tabsByID[id] = nil
        sync()
        if state.tabIDs.isEmpty { newTab() }   // start page (no URL)
    }

    func select(_ id: UUID) {
        state.select(id)
        sync()
    }
}
