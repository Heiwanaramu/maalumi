import SwiftUI
import WebKit
import Combine

// MARK: - FilterList model

struct FilterList: Identifiable, Codable {
    let id: String           // stable key for UserDefaults
    let name: String         // "Cookie notice blocker"
    let source: String       // "EasyList Cookie"
    let url: String          // download URL
    var isEnabled: Bool
    var isBuiltIn: Bool      // false = user-added custom list
}

// MARK: - FilterListManager

/// Single source of truth for all content filter lists.
/// Compiles a merged WKContentRuleList whenever the enabled set changes.
@MainActor
final class FilterListManager: ObservableObject {

    static let shared = FilterListManager()

    // Published so UI reacts to changes
    @Published private(set) var lists: [FilterList]
    @Published private(set) var isCompiling = false
    @Published private(set) var compiledList: WKContentRuleList?

    private let customKey = "maalumi.customFilterLists"
    private let enabledKey = "maalumi.filterListEnabled."

    // ── Built-in lists ───────────────────────────────────────────────────────
    private static let builtIn: [FilterList] = [
        FilterList(id: "easylist",
                   name: "Ads & Trackers (EasyList)",
                   source: "EasyList",
                   url: "https://easylist.to/easylist/easylist.txt",
                   isEnabled: true, isBuiltIn: true),
        FilterList(id: "easyprivacy",
                   name: "Privacy (EasyPrivacy)",
                   source: "EasyPrivacy",
                   url: "https://easylist.to/easylist/easyprivacy.txt",
                   isEnabled: true, isBuiltIn: true),
        FilterList(id: "ublock-unbreak",
                   name: "uBO Unbreak",
                   source: "uBlock Origin",
                   url: "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/unbreak.txt",
                   isEnabled: true, isBuiltIn: true),
        FilterList(id: "cookie-notices",
                   name: "Cookie notice blocker",
                   source: "EasyList Cookie",
                   url: "https://secure.fanboy.co.nz/fanboy-cookie.txt",
                   isEnabled: true, isBuiltIn: true),
        FilterList(id: "annoyances",
                   name: "Annoying distractions blocker",
                   source: "Fanboy's Annoyances + uBO Annoyances",
                   url: "https://secure.fanboy.co.nz/fanboy-annoyance.txt",
                   isEnabled: false, isBuiltIn: true),
        FilterList(id: "anti-ai",
                   name: "AI suggestions blocker",
                   source: "Anti-AI Suggestions Filters",
                   url: "https://raw.githubusercontent.com/laylavish/uBlockOrigin-HUGE-AI-Blocklist/main/list.txt",
                   isEnabled: false, isBuiltIn: true),
        FilterList(id: "newsletter",
                   name: "Newsletter popup blocker",
                   source: "Fanboy's Anti-Newsletter",
                   url: "https://secure.fanboy.co.nz/fanboy-antifonts.txt",
                   isEnabled: false, isBuiltIn: true),
        FilterList(id: "social-widgets",
                   name: "Social media widgets blocker",
                   source: "Fanboy's Social Blocking",
                   url: "https://secure.fanboy.co.nz/fanboy-social.txt",
                   isEnabled: false, isBuiltIn: true),
        FilterList(id: "mobile-popups",
                   name: "Mobile app popups",
                   source: "Fanboy's Mobile",
                   url: "https://secure.fanboy.co.nz/fanboy-mobile.txt",
                   isEnabled: false, isBuiltIn: true),
    ]

    private init() {
        // Load built-in lists, restoring saved enabled state
        var merged = Self.builtIn
        for i in merged.indices {
            let key = enabledKey + merged[i].id
            if let saved = UserDefaults.standard.object(forKey: key) as? Bool {
                merged[i].isEnabled = saved
            }
        }
        // Append user custom lists
        if let data = UserDefaults.standard.data(forKey: customKey),
           let custom = try? JSONDecoder().decode([FilterList].self, from: data) {
            merged.append(contentsOf: custom)
        }
        self.lists = merged
    }

    // MARK: - Toggle

    func toggle(id: String) {
        guard let i = lists.firstIndex(where: { $0.id == id }) else { return }
        lists[i].isEnabled.toggle()
        UserDefaults.standard.set(lists[i].isEnabled, forKey: enabledKey + id)
        recompile()
    }

    // MARK: - Add custom list

    func addCustomList(urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, URL(string: trimmed) != nil else { return }
        let id = "custom-\(UUID().uuidString.prefix(8))"
        let name = URL(string: trimmed)?.host ?? trimmed
        let list = FilterList(id: id, name: name, source: trimmed, url: trimmed, isEnabled: true, isBuiltIn: false)
        lists.append(list)
        persistCustomLists()
        recompile()
    }

    func removeCustomList(id: String) {
        lists.removeAll { $0.id == id && !$0.isBuiltIn }
        persistCustomLists()
        recompile()
    }

    private func persistCustomLists() {
        let custom = lists.filter { !$0.isBuiltIn }
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: customKey)
        }
    }

    // MARK: - Compile

    /// Compile content rule lists via LumiShieldsCore with chunking safeguards.
    func recompile() {
        guard !isCompiling else { return }
        isCompiling = true
        let dummyUCC = WKUserContentController()
        let rules = buildRuleDictionaries()

        LumiShieldsCore.shared.compileAndApplyRules(rules: rules, to: dummyUCC) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.compiledList = LumiShieldsCore.shared.compiledRuleLists.first
                self.isCompiling  = false
                LumiShieldsCore.shared.updateAllRegisteredWebViews()
                AdBlockRuleList.shared.updateCompiledList(self.compiledList)
            }
        }
    }

    /// Build [[String: Any]] rule dictionaries from enabled filter IDs.
    func buildRuleDictionaries() -> [[String: Any]] {
        var rules: [[String: Any]] = []
        let enabled = Set(lists.filter { $0.isEnabled }.map { $0.id })

        rules += baseAdRules()

        if enabled.contains("easyprivacy") || enabled.contains("easylist") {
            rules += trackerRules()
        }
        if enabled.contains("cookie-notices") {
            rules += cookieRules()
        }
        if enabled.contains("annoyances") || enabled.contains("newsletter") {
            rules += annoyanceRules()
        }
        if enabled.contains("social-widgets") {
            rules += socialRules()
        }
        return rules
    }

    private func buildJSON() -> String {
        let rules = buildRuleDictionaries()
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }

    // MARK: - Rule sets

    private func baseAdRules() -> [[String: Any]] { [
        rule(".*\\.doubleclick\\.net.*"),
        rule(".*googlesyndication\\.com.*"),
        rule(".*youtube\\.com/api/stats/ads.*"),
        rule(".*googleadservices\\.com.*"),
        rule(".*adservice\\.google\\..*"),
        rule(".*pagead2\\.googlesyndication\\.com.*"),
        rule(".*securepubads\\.g\\.doubleclick\\.net.*"),
        rule(".*\\.moatads\\.com.*"),
        rule(".*adnxs\\.com.*"),
        rule(".*\\.advertising\\.com.*"),
        rule(".*scorecardresearch\\.com.*"),
        rule(".*\\.quantserve\\.com.*"),
        rule(".*ads\\.pubmatic\\.com.*"),
        rule(".*\\.rubiconproject\\.com.*"),
        rule(".*\\.criteo\\.com.*"),
        rule(".*\\.criteo\\.net.*"),
        rule(".*amazon-adsystem\\.com.*"),
        rule(".*\\.media\\.net.*"),
        rule(".*\\.taboola\\.com.*"),
        rule(".*\\.outbrain\\.com.*"),
        rule(".*\\.revcontent\\.com.*"),
        rule(".*\\.mgid\\.com.*"),
        rule(".*\\.popads\\.net.*"),
        rule(".*\\.popcash\\.net.*"),
        rule(".*\\.bidswitch\\.net.*"),
        rule(".*\\.smartadserver\\.com.*"),
        rule(".*\\.casalemedia\\.com.*"),
        rule(".*\\.openx\\.net.*"),
        rule(".*\\.adroll\\.com.*"),
        rule(".*\\.inmobi\\.com.*"),
        rule(".*\\.adcolony\\.com.*"),
        rule(".*\\.vungle\\.com.*"),
        rule(".*\\.applovin\\.com.*"),
        rule(".*\\.ironsrc\\.com.*"),
        rule(".*\\.chartboost\\.com.*"),
        rule(".*\\.zedo\\.com.*"),
        rule(".*\\.serving-sys\\.com.*"),
        rule(".*\\.exponential\\.com.*"),
        rule(".*\\.tribalfusion\\.com.*"),
        rule(".*\\.trafficfactory\\.biz.*"),
        rule(".*\\.exoclick\\.com.*"),
        rule(".*\\.juicyads\\.com.*"),
        rule(".*\\.adform\\.net.*"),
        rule(".*\\.sovrn\\.com.*"),
        rule(".*\\.indexexchange\\.com.*"),
        rule(".*\\.yieldmo\\.com.*"),
        rule(".*\\.sharethrough\\.com.*"),
        rule(".*\\.triplelift\\.com.*"),
        rule(".*\\.teads\\.tv.*"),
        rule(".*adcontent.*"),
        rule(".*/ads/.*"),
        rule(".*/ad/.*")
    ]}

    private func trackerRules() -> [[String: Any]] { [
        rule(".*\\.hotjar\\.com.*"),
        rule(".*\\.mixpanel\\.com.*"),
        rule(".*\\.segment\\.com.*"),
        rule(".*\\.amplitude\\.com.*"),
        rule(".*\\.fullstory\\.com.*"),
        rule(".*\\.clarity\\.ms.*"),
        rule(".*\\.heap\\.io.*"),
        rule(".*\\.mouseflow\\.com.*"),
        rule(".*\\.intercom\\.io.*"),
        rule(".*\\.pingdom\\.net.*"),
        rule(".*\\.omtrdc\\.net.*"),
        rule(".*\\.demdex\\.net.*"),
        rule(".*\\.google-analytics\\.com.*"),
        rule(".*\\.googletagmanager\\.com/gtm\\.js.*"),
        rule(".*\\.facebook\\.net/.*/fbevents\\.js.*"),
        rule(".*\\.facebook\\.com/tr.*"),
        rule(".*analytics\\.tiktok\\.com.*"),
        rule(".*mc\\.yandex\\.ru.*"),
        rule(".*\\.crazyegg\\.com.*")
    ]}

    private func cookieRules() -> [[String: Any]] { [
        rule(".*\\.cookielaw\\.org.*"),
        rule(".*\\.onetrust\\.com.*"),
        rule(".*\\.trustarc\\.com.*"),
        rule(".*\\.consentmanager\\.net.*"),
        rule(".*\\.cookiebot\\.com.*"),
        rule(".*\\.didomi\\.io.*"),
        rule(".*\\.usercentrics\\.eu.*"),
        rule(".*\\.cookieyes\\.com.*"),
        rule(".*\\.iubenda\\.com.*")
    ]}

    private func annoyanceRules() -> [[String: Any]] { [
        rule(".*\\.pushcrew\\.com.*"),
        rule(".*\\.push\\.io.*"),
        rule(".*\\.onesignal\\.com.*"),
        rule(".*\\.wonderpush\\.com.*"),
        rule(".*\\.webpushr\\.com.*"),
        rule(".*\\.outbrain\\.com.*"),
        rule(".*\\.taboola\\.com.*"),
        rule(".*\\.revcontent\\.com.*"),
        rule(".*\\.nativo\\.com.*"),
        rule(".*\\.content\\.ad.*")
    ]}

    private func socialRules() -> [[String: Any]] { [
        rule(".*\\.facebook\\.net/en_US/all\\.js.*"),
        rule(".*\\.facebook\\.net/en_US/sdk\\.js.*"),
        rule(".*\\.twitter\\.com/widgets.*"),
        rule(".*\\.platform\\.twitter\\.com.*"),
        rule(".*\\.linkedin\\.com/analytics.*"),
        rule(".*assets\\.pinterest\\.com.*")
    ]}

    private func rule(_ urlFilter: String) -> [String: Any] {
        [
            "trigger": ["url-filter": urlFilter],
            "action": ["type": "block"]
        ]
    }
}

// MARK: - Filter Lists Settings UI

struct FilterListsView: View {
    @StateObject private var manager = FilterListManager.shared
    @State private var customURL  = ""
    @State private var searchText = ""
    @State private var showAll    = false
    @State private var devMode    = false
    @FocusState private var urlFieldFocused: Bool

    private var visibleLists: [FilterList] {
        let base = showAll ? manager.lists : Array(manager.lists.prefix(7))
        if searchText.isEmpty { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.source.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // ── Filter lists section ─────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("Filter lists")
                    .font(.headline)
                Text("Additional popular community lists. Note that enabling too many filters will degrade browsing speeds.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Filter lists", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.25)))
                
                // List rows
                VStack(spacing: 0) {
                    ForEach(visibleLists) { list in
                        FilterListRow(list: list, onToggle: {
                            manager.toggle(id: list.id)
                        }, onRemove: list.isBuiltIn ? nil : {
                            manager.removeCustomList(id: list.id)
                        })
                        if list.id != visibleLists.last?.id {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2)))
                
                // Action buttons
                HStack(spacing: 10) {
                    Button(showAll ? "Show less" : "Show full list") {
                        showAll.toggle()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Update lists") {
                        manager.recompile()
                    }
                    .buttonStyle(.bordered)
                    .disabled(manager.isCompiling)
                    
                    if manager.isCompiling {
                        ProgressView().scaleEffect(0.6)
                    }
                    Spacer()
                }
            }
            
            Divider()
            
            // ── Add custom filter list ───────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("Add custom filter lists")
                    .font(.headline)
                Text("Add additional lists created and maintained by your trusted community.\nOnly subscribe to lists from entities you trust. Your browser will periodically check for list updates from the URL you enter, revealing your IP address to their server.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    TextField("Enter filter list URL", text: $customURL)
                        .textFieldStyle(.plain)
                        .focused($urlFieldFocused)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                            urlFieldFocused ? Color.accentColor : Color.gray.opacity(0.25)))
                        .onSubmit { addCustomList() }
                    
                    Button("Add") { addCustomList() }
                        .buttonStyle(.borderedProminent)
                        .disabled(customURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                
                // User-added custom lists
                let custom = manager.lists.filter { !$0.isBuiltIn }
                if !custom.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(custom) { list in
                            FilterListRow(list: list, onToggle: {
                                manager.toggle(id: list.id)
                            }, onRemove: {
                                manager.removeCustomList(id: list.id)
                            })
                            if list.id != custom.last?.id { Divider().padding(.leading, 36) }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2)))
                }
            }
            
            Divider()
            
            // ── Developer mode ───────────────────────────────────────────
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Developer mode").font(.callout.weight(.medium))
                    Text("Allow adding custom filters and scriptlets")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $devMode).labelsHidden()
            }
        }
    }

    private func addCustomList() {
        let t = customURL.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        manager.addCustomList(urlString: t)
        customURL = ""
    }
}

// MARK: - Filter List Row

private struct FilterListRow: View {
    let list: FilterList
    let onToggle: () -> Void
    var onRemove: (() -> Void)?

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { list.isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 1) {
                Text(list.name)
                    .font(.callout.weight(.medium))
                Text(list.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !list.isBuiltIn, let remove = onRemove {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(hovered ? 1 : 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}
