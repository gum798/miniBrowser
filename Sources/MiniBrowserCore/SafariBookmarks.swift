import Foundation

/// Reads macOS Safari's bookmarks live from `~/Library/Safari/Bookmarks.plist`.
/// No import or sync step — call `read()` each time you need the current list.
///
/// Note: that folder is TCC-protected, so the app needs "Full Disk Access"
/// granted by the user; without it `read()` returns `.denied`.
public enum SafariBookmarks {
    public static let defaultLocation = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Safari/Bookmarks.plist")

    public enum Access: Equatable {
        case ok([Bookmark])
        case denied        // file present but unreadable — needs Full Disk Access
        case unavailable   // no Safari bookmarks file here
    }

    public static func read(from url: URL = defaultLocation) -> Access {
        do {
            return .ok(parse(try Data(contentsOf: url)))
        } catch {
            return (error as NSError).code == NSFileReadNoSuchFileError ? .unavailable : .denied
        }
    }

    /// Pure: parse a Safari Bookmarks.plist into a flat, de-duplicated bookmark
    /// list (folders flattened, proxy/history nodes skipped, first URL wins).
    public static func parse(_ data: Data) -> [Bookmark] {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = root as? [String: Any] else { return [] }
        var out: [Bookmark] = []
        var seen = Set<String>()
        collect(dict, into: &out, seen: &seen)
        return out
    }

    private static func collect(_ node: [String: Any], into out: inout [Bookmark], seen: inout Set<String>) {
        switch node["WebBookmarkType"] as? String {
        case "WebBookmarkTypeLeaf":
            guard let s = node["URLString"] as? String,
                  let url = URL(string: s), seen.insert(s).inserted else { return }
            let title = (node["URIDictionary"] as? [String: Any])?["title"] as? String
            out.append(Bookmark(title: (title?.isEmpty == false) ? title! : s, url: url))
        case "WebBookmarkTypeList":
            for case let child as [String: Any] in (node["Children"] as? [Any] ?? []) {
                collect(child, into: &out, seen: &seen)
            }
        default:
            break   // WebBookmarkTypeProxy (History / Reading List container) and unknown
        }
    }
}
