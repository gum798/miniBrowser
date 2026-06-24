import SwiftUI

struct BottomToolbar: View {
    @ObservedObject var tab: Tab
    @ObservedObject var boss: BossMode
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
            Menu {
                Button { tab.zoomIn() }  label: { Label("글자 크게", systemImage: "plus.magnifyingglass") }
                Button { tab.zoomOut() } label: { Label("글자 작게", systemImage: "minus.magnifyingglass") }
                Button { tab.resetZoom() } label: {
                    Label("원래 크기 (\(Int(tab.zoom * 100))%)", systemImage: "1.magnifyingglass")
                }
                .disabled(tab.url == nil)
                Divider()
                Button { tab.toggleInvert() } label: {
                    Label(tab.inverted ? "색 반전 끄기" : "색 반전", systemImage: "circle.righthalf.filled")
                }
                .disabled(tab.url == nil)
                Divider()
                Button { boss.enabled.toggle() } label: {
                    Label(boss.enabled ? "자리비움 자동 숨김: 켜짐" : "자리비움 자동 숨김: 꺼짐",
                          systemImage: boss.enabled ? "eye.slash" : "eye")
                }
            } label: {
                Image(systemName: "textformat.size")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
            Button(action: onShowTabs) {
                Label("\(tabCount)", systemImage: "square.on.square")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}
