import SwiftUI
import AppKit
import MiniBrowserCore

struct StartPageView: View {
    let bookmarks: [Bookmark]
    let recent: [HistoryEntry]
    /// Live filter from the address bar — empty shows everything.
    var query: String = ""
    let onOpen: (URL) -> Void

    /// Safari bookmarks, read live every time the start page appears.
    @State private var safari: SafariBookmarks.Access = .unavailable

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 16)]

    var body: some View {
        let favorites = filter(bookmarks, \.title, \.url)
        let recents = filter(recent, \.title, \.url)
        let safariItems = filterSafari()

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !favorites.isEmpty {
                    Text("즐겨찾기").font(.headline).padding(.horizontal)
                    grid(favorites)
                }

                safariSection(safariItems)

                if !recents.isEmpty {
                    Text("최근 방문").font(.headline).padding(.horizontal)
                    VStack(spacing: 0) {
                        ForEach(recents) { entry in
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

                if isSearching && favorites.isEmpty && safariItems.isEmpty && recents.isEmpty {
                    Text("‘\(query.trimmingCharacters(in: .whitespacesAndNewlines))’ 검색 결과가 없습니다")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding(.vertical)
        }
        .onAppear(perform: reloadSafari)
    }

    @ViewBuilder private func safariSection(_ items: [Bookmark]) -> some View {
        switch safari {
        case .ok where !items.isEmpty:
            HStack {
                Text("Safari 북마크").font(.headline)
                Spacer()
                Text("\(items.count)").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            grid(items)
        case .denied where !isSearching:
            permissionCard
        default:
            EmptyView()
        }
    }

    private func grid(_ items: [Bookmark]) -> some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(items, id: \.url) { tile($0) }
        }
        .padding(.horizontal)
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Safari 북마크").font(.headline)
            Text("Safari 북마크를 보려면 ‘전체 디스크 접근’ 권한이 필요합니다. 시스템 설정에서 miniBrowser를 켜고 앱을 다시 실행하세요.")
                .font(.callout).foregroundStyle(.secondary)
            Button("시스템 설정 열기") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary))
        .padding(.horizontal)
    }

    private func tile(_ b: Bookmark) -> some View {
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

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func filter<T>(_ items: [T], _ title: KeyPath<T, String>, _ url: KeyPath<T, URL>) -> [T] {
        items.filter { TextSearch.matches(query, anyOf: [$0[keyPath: title], $0[keyPath: url].absoluteString]) }
    }

    private func filterSafari() -> [Bookmark] {
        guard case .ok(let items) = safari else { return [] }
        return filter(items, \.title, \.url)
    }

    private func reloadSafari() {
        Task.detached(priority: .userInitiated) {
            let result = SafariBookmarks.read()
            await MainActor.run { safari = result }
        }
    }

    private func initials(_ s: String) -> String {
        String(s.prefix(1)).uppercased()
    }
}
