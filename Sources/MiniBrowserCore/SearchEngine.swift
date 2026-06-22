import Foundation

public enum SearchEngine: String, Codable, CaseIterable, Sendable {
    case google

    public func searchURL(query: String) -> URL {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        switch self {
        case .google:
            return URL(string: "https://www.google.com/search?q=\(encoded)")!
        }
    }
}
