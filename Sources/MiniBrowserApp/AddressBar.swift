import SwiftUI
import MiniBrowserCore

struct AddressBar: View {
    @ObservedObject var tab: Tab
    let historyStore: HistoryStore
    let onSubmit: (URL) -> Void

    @State private var text: String = ""
    @State private var editing = false
    @State private var suggestions: [HistoryEntry] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TextField("검색 또는 주소 입력", text: $text, onEditingChanged: { editing = $0 })
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
                    .onChange(of: text) { _, newValue in
                        suggestions = historyStore.suggestions(for: newValue, limit: 6)
                    }
                if tab.isLoading {
                    Button(action: tab.stop) { Image(systemName: "xmark") }
                } else {
                    Button(action: tab.reload) { Image(systemName: "arrow.clockwise") }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            if tab.isLoading {
                ProgressView(value: tab.progress).progressViewStyle(.linear)
            }

            if editing && !suggestions.isEmpty {
                ForEach(suggestions) { entry in
                    Button {
                        onSubmit(entry.url)
                        text = entry.url.absoluteString
                        suggestions = []
                    } label: {
                        HStack {
                            Text(entry.title.isEmpty ? entry.url.absoluteString : entry.title)
                                .lineLimit(1)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                }
            }
        }
        .onChange(of: tab.url) { _, newURL in
            if !editing { text = newURL?.absoluteString ?? "" }
        }
    }

    private func submit() {
        guard let url = URLResolver.resolve(text) else { return }
        onSubmit(url)
        suggestions = []
    }
}
