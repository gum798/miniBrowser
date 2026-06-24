import WebKit
import Combine
import MiniBrowserCore

/// "방해 요소 가리기": while `picking` is on, hovering highlights elements and a
/// click hides the clicked element and remembers it per-site. Remembered hides
/// are re-applied on every load (and persist across restarts).
@MainActor
final class ElementHider: NSObject, ObservableObject {
    static let shared = ElementHider()

    @Published var picking = false {
        didSet {
            let views = webViews.allObjects
            views.forEach { picking ? startPicking($0) : stopPicking($0) }
        }
    }

    private let store = HiddenElementsStore(directory: AppPaths.supportDirectory())
    private let webViews = NSHashTable<WKWebView>.weakObjects()

    /// Wire a tab's web view up to receive picked-element messages.
    func register(_ webView: WKWebView) {
        webViews.add(webView)
        let ucc = webView.configuration.userContentController
        ucc.removeScriptMessageHandler(forName: "mbHide")
        ucc.add(self, name: "mbHide")
    }

    /// Re-apply remembered hides (and re-arm the picker if it's on) after a load.
    func onPageLoaded(_ webView: WKWebView) {
        applyHides(webView)
        if picking { startPicking(webView) }
    }

    /// Forget every element hidden on the current site and reload to bring them back.
    func resetCurrentHost(of webView: WKWebView) {
        guard let host = webView.url?.host else { return }
        store.reset(host: host)
        webView.reload()
    }

    private func applyHides(_ webView: WKWebView) {
        guard let host = webView.url?.host else { return }
        let selectors = store.selectors(host: host)
        guard !selectors.isEmpty else { return }
        let css = selectors.joined(separator: ", ") + "{display:none !important}"
        webView.evaluateJavaScript(
            "(function(){var id='__mbHideStyle__',s=document.getElementById(id);" +
            "if(!s){s=document.createElement('style');s.id=id;(document.head||document.documentElement).appendChild(s);}" +
            "s.textContent=\(Self.jsString(css));})();")
    }

    private func startPicking(_ webView: WKWebView) { webView.evaluateJavaScript(Self.pickerOn) }
    private func stopPicking(_ webView: WKWebView) { webView.evaluateJavaScript(Self.pickerOff) }

    /// Encode a string as a JS/JSON string literal so it embeds safely.
    private static func jsString(_ s: String) -> String {
        guard let data = try? JSONEncoder().encode(s), let str = String(data: data, encoding: .utf8) else { return "\"\"" }
        return str
    }

    private static let pickerOn = """
    (function(){
      if (window.__mbPick) return; window.__mbPick = true;
      function sel(el){
        if (el.id) return '#'+CSS.escape(el.id);
        var parts=[], n=0;
        while (el && el.nodeType===1 && el.tagName!=='HTML' && el.tagName!=='BODY' && n<6){
          var p=el.tagName.toLowerCase(), par=el.parentNode;
          if (par){
            var same=Array.prototype.filter.call(par.children,function(c){return c.tagName===el.tagName;});
            if (same.length>1) p+=':nth-of-type('+(Array.prototype.indexOf.call(same,el)+1)+')';
          }
          parts.unshift(p);
          if (el.id){ parts[0]='#'+CSS.escape(el.id); break; }
          el=el.parentNode; n++;
        }
        return parts.join('>');
      }
      function over(e){ e.target.__mbo=e.target.style.outline; e.target.style.outline='2px solid #ff3b30'; }
      function out(e){ if(e.target.style) e.target.style.outline=e.target.__mbo||''; }
      function clk(e){
        e.preventDefault(); e.stopPropagation();
        var el=e.target, s=sel(el);
        el.style.setProperty('display','none','important'); el.style.outline='';
        try{ window.webkit.messageHandlers.mbHide.postMessage({selector:s,host:location.host}); }catch(x){}
        return false;
      }
      window.__mbOver=over; window.__mbOut=out; window.__mbClk=clk;
      document.addEventListener('mouseover',over,true);
      document.addEventListener('mouseout',out,true);
      document.addEventListener('click',clk,true);
    })();
    """

    private static let pickerOff = """
    (function(){
      if(!window.__mbPick) return;
      document.removeEventListener('mouseover',window.__mbOver,true);
      document.removeEventListener('mouseout',window.__mbOut,true);
      document.removeEventListener('click',window.__mbClk,true);
      var o=document.querySelectorAll('*');
      window.__mbPick=false;
    })();
    """
}

extension ElementHider: WKScriptMessageHandler {
    nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "mbHide",
              let body = message.body as? [String: Any],
              let selector = body["selector"] as? String,
              let host = body["host"] as? String else { return }
        Task { @MainActor in self.store.add(selector, host: host) }
    }
}
