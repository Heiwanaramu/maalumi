import WebKit
import Foundation

/// Core engine for LumiShields content blocking.
/// Manages chunked compilation safeguards (avoiding WebKit's 150k rule limit),
/// rule list caching, tab propagation, and WebView registration.
@MainActor
final class LumiShieldsCore: ObservableObject {
    static let shared = LumiShieldsCore()

    @Published private(set) var areRulesReady: Bool = false
    private(set) var compiledRuleLists: [WKContentRuleList] = []
    private var isCompiling: Bool = false
    private var pendingCompletions: [() -> Void] = []
    private var registeredWebViews: [WeakWebView] = []

    private struct WeakWebView {
        weak var webView: WKWebView?
    }

    private init() {}

    // MARK: - Registration

    func register(_ webView: WKWebView) {
        registeredWebViews.removeAll { $0.webView == nil }
        registeredWebViews.append(WeakWebView(webView: webView))
    }

    // MARK: - Task 1: macOS-Optimized Heavy Chunking

    /// Compiles rules using macOS concurrent dispatch queues, slicing rules just under the
    /// WebKit 150,000 hard ceiling (149,000 rules per chunk).
    func compileHeavyweightRules(rules: [[String: Any]], to userContentController: WKUserContentController, completion: @escaping () -> Void) {
        let maxWebKitLimit = 149_000 // Safely under the 150k hard-coded ceiling
        let chunks: [[[String: Any]]]
        if rules.isEmpty {
            chunks = []
        } else {
            chunks = stride(from: 0, to: rules.count, by: maxWebKitLimit).map {
                Array(rules[$0..<min($0 + maxWebKitLimit, rules.count)])
            }
        }

        if chunks.isEmpty {
            self.compiledRuleLists = []
            self.areRulesReady = true
            self.isCompiling = false
            print("🛡️ [LumiShields-Mac] All rule chunks successfully loaded into memory.")
            completion()
            return
        }

        self.isCompiling = true
        let dispatchGroup = DispatchGroup()
        let backgroundQueue = DispatchQueue(label: "com.maalumi.shieldCompiler", attributes: .concurrent)
        var newlyCompiled = [WKContentRuleList?](repeating: nil, count: chunks.count)
        let lock = NSLock()

        for (index, chunk) in chunks.enumerated() {
            dispatchGroup.enter()

            backgroundQueue.async {
                guard let data = try? JSONSerialization.data(withJSONObject: chunk),
                      let jsonString = String(data: data, encoding: .utf8) else {
                    dispatchGroup.leave()
                    return
                }

                let identifier = "MaalumiShields_MaxChunk_\(index)"

                guard let store = WKContentRuleListStore.default() else {
                    print("❌ [LumiShields-Mac] WKContentRuleListStore unavailable for chunk \(index)")
                    dispatchGroup.leave()
                    return
                }

                store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: jsonString) { ruleList, error in
                    if let error = error {
                        print("❌ [LumiShields-Mac] Failed to compile heavy chunk \(index): \(error.localizedDescription)")
                    } else if let ruleList = ruleList {
                        lock.lock()
                        newlyCompiled[index] = ruleList
                        lock.unlock()

                        DispatchQueue.main.async {
                            userContentController.add(ruleList)
                            print("✅ [LumiShields-Mac] Attached heavy chunk \(index) (\(chunk.count) rules)")
                        }
                    }
                    dispatchGroup.leave()
                }
            }
        }

        dispatchGroup.notify(queue: .main) {
            let validLists = newlyCompiled.compactMap { $0 }
            self.compiledRuleLists = validLists
            self.areRulesReady = true
            self.isCompiling = false

            // Remove any leftover chunks from previous compilations with higher indices
            if let store = WKContentRuleListStore.default() {
                store.getAvailableContentRuleListIdentifiers { ids in
                    guard let ids = ids else { return }
                    for id in ids where id.hasPrefix("MaalumiShields_MaxChunk_") {
                        if let idx = Int(id.replacingOccurrences(of: "MaalumiShields_MaxChunk_", with: "")), idx >= chunks.count {
                            store.removeContentRuleList(forIdentifier: id) { _ in }
                        }
                    }
                }
            }

            print("🛡️ [LumiShields-Mac] All rule chunks successfully loaded into memory.")

            let completions = self.pendingCompletions
            self.pendingCompletions.removeAll()
            completions.forEach { $0() }

            completion()
        }
    }

    /// Backwards-compatible alias for compileHeavyweightRules.
    func compileAndApplyRules(rules: [[String: Any]], to userContentController: WKUserContentController, completion: @escaping () -> Void) {
        compileHeavyweightRules(rules: rules, to: userContentController, completion: completion)
    }

    // MARK: - Task 2: Persistent Disk Caching

    /// Precompiles on app launch or loads instantly from disk cache if MaalumiShields_MaxChunk_X
    /// identifiers already exist on disk.
    func precompile(completion: (() -> Void)? = nil) {
        guard !areRulesReady, !isCompiling else {
            completion?()
            return
        }
        isCompiling = true

        guard let store = WKContentRuleListStore.default() else {
            self.isCompiling = false
            completion?()
            return
        }

        store.getAvailableContentRuleListIdentifiers { [weak self] identifiers in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let prefix = "MaalumiShields_MaxChunk_"
                let available = identifiers ?? []

                // Clean up legacy chunks from prior versions if any exist
                for id in available where id.hasPrefix("MaalumiShields_Chunk_") {
                    store.removeContentRuleList(forIdentifier: id) { _ in }
                }

                let matching = available.filter { $0.hasPrefix(prefix) }
                let chunkIndices = matching.compactMap { Int($0.replacingOccurrences(of: prefix, with: "")) }.sorted()

                if !chunkIndices.isEmpty, chunkIndices.first == 0, chunkIndices == Array(0..<chunkIndices.count) {
                    print("💾 [LumiShields-Mac] Found \(chunkIndices.count) cached heavy chunk(s) on disk. Loading from cache...")
                    self.loadCachedChunks(store: store, chunkCount: chunkIndices.count, to: nil) {
                        completion?()
                    }
                } else {
                    print("🔄 [LumiShields-Mac] No matching cached chunks found on disk. Compiling fresh rules...")
                    let dummyUCC = WKUserContentController()
                    let rules = FilterListManager.shared.buildRuleDictionaries()
                    self.compileHeavyweightRules(rules: rules, to: dummyUCC) {
                        completion?()
                    }
                }
            }
        }
    }

    /// Loads cached rule lists from disk in parallel using lookUpContentRuleList.
    private func loadCachedChunks(store: WKContentRuleListStore, chunkCount: Int, to userContentController: WKUserContentController?, completion: @escaping () -> Void) {
        let dispatchGroup = DispatchGroup()
        let backgroundQueue = DispatchQueue(label: "com.maalumi.shieldLoader", attributes: .concurrent)
        var loaded = [WKContentRuleList?](repeating: nil, count: chunkCount)
        let lock = NSLock()

        for index in 0..<chunkCount {
            dispatchGroup.enter()
            backgroundQueue.async {
                let identifier = "MaalumiShields_MaxChunk_\(index)"
                store.lookUpContentRuleList(forIdentifier: identifier) { ruleList, error in
                    if let error = error {
                        print("❌ [LumiShields-Mac] Failed to load cached chunk \(index): \(error.localizedDescription)")
                    } else if let ruleList = ruleList {
                        lock.lock()
                        loaded[index] = ruleList
                        lock.unlock()
                        DispatchQueue.main.async {
                            userContentController?.add(ruleList)
                            print("💾 [LumiShields-Mac] Loaded cached heavy chunk \(index) from disk")
                        }
                    }
                    dispatchGroup.leave()
                }
            }
        }

        dispatchGroup.notify(queue: .main) {
            let validLists = loaded.compactMap { $0 }
            if validLists.count == chunkCount {
                self.compiledRuleLists = validLists
                self.areRulesReady = true
                self.isCompiling = false
                print("🛡️ [LumiShields-Mac] All \(validLists.count) cached rule chunk(s) successfully loaded into memory from disk.")

                let completions = self.pendingCompletions
                self.pendingCompletions.removeAll()
                completions.forEach { $0() }

                completion()
            } else {
                print("⚠️ [LumiShields-Mac] Cache lookup incomplete (\(validLists.count)/\(chunkCount)). Falling back to recompile.")
                let dummyUCC = userContentController ?? WKUserContentController()
                let rules = FilterListManager.shared.buildRuleDictionaries()
                self.compileHeavyweightRules(rules: rules, to: dummyUCC, completion: completion)
            }
        }
    }

    // MARK: - Tab Propagation & Attachment

    /// Attaches all compiled rule lists to the given userContentController.
    /// If rules are not yet compiled or loaded, buffers the completion until ready.
    func attachRules(to userContentController: WKUserContentController, completion: @escaping () -> Void) {
        if areRulesReady {
            for (index, ruleList) in compiledRuleLists.enumerated() {
                userContentController.add(ruleList)
                print("✅ [LumiShields-Mac] Attached heavy chunk \(index) (\(ruleList.identifier ?? "chunk"))")
            }
            completion()
        } else {
            pendingCompletions.append { [weak self, weak userContentController] in
                guard let self, let ucc = userContentController else { return }
                for (index, ruleList) in self.compiledRuleLists.enumerated() {
                    ucc.add(ruleList)
                    print("✅ [LumiShields-Mac] Attached heavy chunk \(index) (\(ruleList.identifier ?? "chunk"))")
                }
                completion()
            }
            if !isCompiling {
                precompile()
            }
        }
    }

    // MARK: - Update Active Tabs on Recompilation

    func updateAllRegisteredWebViews() {
        let shieldsOn = UserDefaults.standard.object(forKey: "kShieldsAdBlockEnabled") as? Bool ?? true
        for entry in registeredWebViews {
            guard let wv = entry.webView else { continue }
            let ucc = wv.configuration.userContentController
            ucc.removeAllContentRuleLists()
            if shieldsOn {
                for (index, ruleList) in compiledRuleLists.enumerated() {
                    ucc.add(ruleList)
                    print("✅ [LumiShields-Mac] Attached heavy chunk \(index) (\(ruleList.identifier ?? "chunk"))")
                }
            }
        }
    }
}
