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
