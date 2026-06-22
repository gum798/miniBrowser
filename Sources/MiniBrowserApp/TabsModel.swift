import Foundation
import WebKit
import Combine
import MiniBrowserCore

@MainActor
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
        if tabs.isEmpty { newTab() }   // start page (no URL)
    }

    func select(_ id: UUID) {
        state.select(id)
        sync()
    }
}
