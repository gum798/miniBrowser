import SwiftUI

struct TabSwitcherView: View {
    @ObservedObject var model: TabsModel
    @Binding var isPresented: Bool

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("새 탭") {
                    model.newTab()      // start page
                    isPresented = false
                }
                Spacer()
                Button("완료") { isPresented = false }
            }
            .padding(12)
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.tabs) { tab in
                        TabCard(tab: tab,
                                isActive: tab.id == model.activeID,
                                onSelect: { model.select(tab.id); isPresented = false },
                                onClose: { model.close(tab.id) })
                    }
                }
                .padding(12)
            }
        }
    }
}

private struct TabCard: View {
    @ObservedObject var tab: Tab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tab.title.isEmpty ? "새 탭" : tab.title).lineLimit(1).font(.caption.bold())
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
            Text((tab.url ?? tab.pendingURL)?.host() ?? "").lineLimit(1).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(height: 80, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(isActive ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
