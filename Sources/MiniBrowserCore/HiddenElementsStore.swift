import Foundation

/// Per-site list of CSS selectors the user chose to hide ("방해 요소 가리기"),
/// persisted to hidden-elements.json so hides survive revisits and restarts.
public final class HiddenElementsStore {
    private let fileURL: URL
    private var byHost: [String: [String]]

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("hidden-elements.json")
        self.byHost = Self.load(from: fileURL)
    }

    public func selectors(host: String) -> [String] { byHost[host] ?? [] }

    public func add(_ selector: String, host: String) {
        var list = byHost[host] ?? []
        guard !list.contains(selector) else { return }
        list.append(selector)
        byHost[host] = list
        persist()
    }

    public func reset(host: String) {
        byHost[host] = nil
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(byHost) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> [String: [String]] {
        guard let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return map
    }
}
