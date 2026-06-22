import SwiftUI
import MiniBrowserCore

struct StartPageView: View {
    let bookmarks: [Bookmark]
    let recent: [HistoryEntry]
    let onOpen: (URL) -> Void

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !bookmarks.isEmpty {
                    Text("즐겨찾기").font(.headline).padding(.horizontal)
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(bookmarks) { b in
                            Button { onOpen(b.url) } label: {
                                VStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(.quaternary)
                                        .frame(width: 56, height: 56)
                                        .overlay(Text(initials(b.title)).font(.title3.bold()))
                                    Text(b.title).font(.caption2).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }

                if !recent.isEmpty {
                    Text("최근 방문").font(.headline).padding(.horizontal)
                    VStack(spacing: 0) {
                        ForEach(recent) { entry in
                            Button { onOpen(entry.url) } label: {
                                HStack {
                                    Text(entry.title.isEmpty ? entry.url.absoluteString : entry.title)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 8).padding(.horizontal)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
            .padding(.vertical)
        }
    }

    private func initials(_ s: String) -> String {
        String(s.prefix(1)).uppercased()
    }
}
