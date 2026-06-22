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
