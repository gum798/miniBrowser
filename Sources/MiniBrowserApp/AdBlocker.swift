import WebKit
import Combine
import MiniBrowserCore

/// Compiles the ad/tracker content-blocker rules once and applies them to every
/// tab's web view (iPhone-Safari-style ad removal). Shared across tabs; toggle
/// `enabled` to turn it off. Takes effect on the next page load.
@MainActor
final class AdBlocker: ObservableObject {
    static let shared = AdBlocker()

    @Published var enabled = true {
        didSet { applyAll() }
    }

    private var ruleList: WKContentRuleList?
    private let webViews = NSHashTable<WKWebView>.weakObjects()

    private init() { compile() }

    /// Track a tab's web view and apply the blocker to it.
    func register(_ webView: WKWebView) {
        webViews.add(webView)
        apply(to: webView)
    }

    private func compile() {
        WKContentRuleListStore.default()?.compileContentRuleList(
            forIdentifier: "miniBrowserAdBlock",
            encodedContentRuleList: AdBlockRules.json
        ) { [weak self] list, error in
            // WebKit delivers this on the main thread.
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error {
                    FileHandle.standardError.write(Data("adblock compile failed: \(error)\n".utf8))
                    return
                }
                self.ruleList = list
                self.applyAll()
            }
        }
    }

    private func applyAll() { webViews.allObjects.forEach { apply(to: $0) } }

    private func apply(to webView: WKWebView) {
        guard let ruleList else { return }
        let ucc = webView.configuration.userContentController
        if enabled { ucc.add(ruleList) } else { ucc.remove(ruleList) }
    }
}
