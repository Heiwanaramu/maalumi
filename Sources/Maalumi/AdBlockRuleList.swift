import WebKit
import os.log

/// Legacy adapter wrapping LumiShieldsCore.
/// All WebViewModel instances share the cached chunked lists compiled by LumiShieldsCore.
@MainActor
final class AdBlockRuleList {
    static let shared = AdBlockRuleList()

    var compiledRuleList: WKContentRuleList? {
        LumiShieldsCore.shared.compiledRuleLists.first
    }

    private init() {}

    // MARK: - Registration

    func register(_ webView: WKWebView) {
        LumiShieldsCore.shared.register(webView)
    }

    // MARK: - Update from FilterListManager

    func updateCompiledList(_ list: WKContentRuleList?) {
        LumiShieldsCore.shared.updateAllRegisteredWebViews()
    }

    // MARK: - Precompile on launch

    func precompile() {
        LumiShieldsCore.shared.precompile()
    }

    // MARK: - Deliver to WebViews

    func getRuleList(completion: @escaping (WKContentRuleList?) -> Void) {
        if let list = compiledRuleList {
            completion(list)
        } else {
            LumiShieldsCore.shared.attachRules(to: WKUserContentController()) {
                completion(LumiShieldsCore.shared.compiledRuleLists.first)
            }
        }
    }
}
