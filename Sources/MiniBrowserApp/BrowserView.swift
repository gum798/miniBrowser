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
