import SwiftUI
import WebKit
import MaalumiCore

// MARK: - ClickThroughWebView
// Internal (not private) so WebViewModel can instantiate it.
// acceptsFirstMouse = true means toolbar buttons and address bar respond
// on the FIRST click even when the window is not in focus.

final class ClickThroughWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - MaalumiWebView (NSViewRepresentable)

struct MaalumiWebView: NSViewRepresentable {
    @ObservedObject var viewModel: WebViewModel

    func makeCoordinator() -> Coordinator { Coordinator(viewModel: viewModel) }

    func makeNSView(context: Context) -> WKWebView {
        let wv = viewModel.webView
        wv.uiDelegate         = context.coordinator
        wv.navigationDelegate = context.coordinator
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    // MARK: Coordinator

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        let viewModel: WebViewModel
        init(viewModel: WebViewModel) { self.viewModel = viewModel }

        // Intercept target="_blank" links — load in current frame instead of dropping
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil ||
               navigationAction.targetFrame?.isMainFrame == false {
                webView.load(navigationAction.request)
            }
            return nil
        }

        // Allow all standard navigation — never silently drop a click
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
            switch scheme {
            case "http", "https", "blob", "data", "about", "":
                decisionHandler(.allow)
            case "mailto", "tel", "facetime", "maps":
                if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
                decisionHandler(.cancel)
            default:
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            viewModel.syncNavigationState()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            viewModel.syncNavigationState()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            viewModel.syncNavigationState()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            viewModel.syncNavigationState()
        }
    }
}
