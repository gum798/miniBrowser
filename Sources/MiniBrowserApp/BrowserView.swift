import SwiftUI
import AppKit
import MiniBrowserCore

struct BrowserView: View {
    @StateObject private var model = TabsModel()
    @StateObject private var boss = BossMode()
    @State private var showTabs = false
    @State private var keyMonitor: Any?
    private let historyStore = HistoryStore(directory: AppPaths.supportDirectory())
    private let bookmarkStore = BookmarkStore(directory: AppPaths.supportDirectory())

    var body: some View {
        Group {
            if showTabs {
                TabSwitcherView(model: model, isPresented: $showTabs)
            } else if let tab = model.active {
                TabContentView(
                    tab: tab,
                    model: model,
                    historyStore: historyStore,
                    bookmarkStore: bookmarkStore,
                    boss: boss,
                    onShowTabs: { showTabs = true }
                )
                .id(tab.id)   // rebind chrome when the active tab changes; web view persists in the model
            }
        }
        .background(WindowReader { boss.attach($0) })   // boss key: shrink when idle
        .onAppear {
            if model.tabs.isEmpty { model.newTab() }   // start page
            installZoomKeys()
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }

    /// ⌘+ / ⌘= (zoom in), ⌘- (zoom out), ⌘0 (reset) on the active tab's page.
    /// A local key monitor is used (instead of SwiftUI shortcuts/commands) so it
    /// fires regardless of focus or menu state, even while the web view is first
    /// responder.
    private func installZoomKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command),
                  let tab = model.active, tab.url != nil else { return event }
            switch event.charactersIgnoringModifiers {
            case "=", "+": tab.zoomIn();    return nil
            case "-":      tab.zoomOut();   return nil
            case "0":      tab.resetZoom(); return nil
            default:       return event
            }
        }
    }
}

/// Per-tab chrome + content. Observes the active `tab` directly so the view
/// switches between the start page and the web view as `tab.url` changes.
/// (BrowserView observes only the TabsModel, which does not republish an
/// individual tab's changes — without this the web view would never mount and
/// `webView.load` would run on a detached, never-rendering WKWebView.)
private struct TabContentView: View {
    @ObservedObject var tab: Tab
    let model: TabsModel
    let historyStore: HistoryStore
    let bookmarkStore: BookmarkStore
    let boss: BossMode
    let onShowTabs: () -> Void

    @State private var bookmarkTick = 0   // bump to refresh bookmark-derived views
    @State private var addressText = ""   // what's typed in the address bar (= start-page filter)

    var body: some View {
        VStack(spacing: 0) {
            AddressBar(tab: tab, historyStore: historyStore, onSubmit: { tab.load($0) }, text: $addressText)
            Divider()
            ZStack {
                if tab.url == nil {
                    StartPageView(
                        bookmarks: bookmarkStore.all(),
                        recent: historyStore.recent(limit: 12),
                        query: addressText,
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
                boss: boss,
                tabCount: model.tabs.count,
                isBookmarked: isBookmarked(tab.url),
                onToggleBookmark: { toggleBookmark(tab) },
                onShowTabs: onShowTabs
            )
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
