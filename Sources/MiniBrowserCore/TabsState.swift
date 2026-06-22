import Foundation

public struct TabsState: Equatable, Sendable {
    public private(set) var tabIDs: [UUID] = []
    public private(set) var activeID: UUID?

    public init() {}

    public mutating func add(_ id: UUID) {
        tabIDs.append(id)
        activeID = id
    }

    public mutating func select(_ id: UUID) {
        if tabIDs.contains(id) { activeID = id }
    }

    public mutating func close(_ id: UUID) {
        guard let idx = tabIDs.firstIndex(of: id) else { return }
        let wasActive = (activeID == id)
        tabIDs.remove(at: idx)
        guard wasActive else { return }
        if tabIDs.isEmpty {
            activeID = nil
        } else {
            // next neighbor if it exists at the same index, else the previous (now-last)
            activeID = tabIDs[min(idx, tabIDs.count - 1)]
        }
    }

    public mutating func move(from: Int, to: Int) {
        guard tabIDs.indices.contains(from), to >= 0, to <= tabIDs.count else { return }
        let id = tabIDs.remove(at: from)
        tabIDs.insert(id, at: min(to, tabIDs.count))
    }
}
