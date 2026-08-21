import SwiftUI
import MiniBrowserCore

struct BottomToolbar: View {
    @ObservedObject var tab: Tab
    @ObservedObject var boss: BossMode
    @ObservedObject private var adBlocker = AdBlocker.shared
    @ObservedObject private var hider = ElementHider.shared
    @ObservedObject private var settings = AppSettings.shared
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
                Button { settings.inverted.toggle() } label: {
                    Label(settings.inverted ? "색 반전 끄기" : "색 반전 (전체)",
                          systemImage: "circle.righthalf.filled")
                }
                Divider()
                Button { hider.picking.toggle() } label: {
                    Label(hider.picking ? "방해 요소 가리기: 켜짐 (요소 하나 클릭)" : "방해 요소 가리기",
                          systemImage: hider.picking ? "eye.slash.circle.fill" : "eye.slash.circle")
                }
                Button { hider.resetCurrentHost(of: tab.webView) } label: {
                    Label("이 페이지에서 가린 요소 초기화", systemImage: "arrow.uturn.backward")
                }
                .disabled(tab.url == nil)
                Divider()
                Button { tab.hardReset() } label: {
                    Label("페이지 강제 리셋 (글자 깨짐 복구)", systemImage: "arrow.clockwise.circle")
                }
                .disabled(tab.url == nil)
                Divider()
                Button { adBlocker.enabled.toggle() } label: {
                    Label(adBlocker.enabled ? "광고 차단: 켜짐" : "광고 차단: 꺼짐",
                          systemImage: adBlocker.enabled ? "hand.raised.fill" : "hand.raised")
                }
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
            Slider(value: $settings.windowOpacity, in: Settings.minWindowOpacity...1) {
                EmptyView()
            } minimumValueLabel: {
                Image(systemName: "circle.dotted")
            } maximumValueLabel: {
                Image(systemName: "circle.fill")
            }
            .controlSize(.mini)
            .frame(width: 80)
            .help("창 투명도 (\(Int(settings.windowOpacity * 100))%)")
            Spacer()
            Button(action: onShowTabs) {
                Label("\(tabCount)", systemImage: "square.on.square")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}
