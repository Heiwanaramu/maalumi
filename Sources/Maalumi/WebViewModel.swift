import SwiftUI
import WebKit
import Combine
import os.log
import MaalumiCore

// MARK: - WebViewModel

@MainActor
final class WebViewModel: ObservableObject {
    let webView: WKWebView

    @Published var urlString:        String = ""
    @Published var pageTitle:        String = ""
    @Published var canGoBack:        Bool   = false
    @Published var canGoForward:     Bool   = false
    @Published var isLoading:        Bool   = false
    @Published var areShieldsActive: Bool   = false

    private var pendingRequest:         URLRequest?
    private var urlObservation:         NSKeyValueObservation?
    private var canGoBackObservation:   NSKeyValueObservation?
    private var canGoForwardObservation:NSKeyValueObservation?
    private var titleObservation:       NSKeyValueObservation?
    private var isLoadingObservation:   NSKeyValueObservation?
    private var defaultsToken:          NSObjectProtocol?

    init() {
        let configuration = WKWebViewConfiguration()

        // ── Persistent data store (logins, cookies, cache survive restarts) ──
        configuration.websiteDataStore = .default()

        // ── Media playback ────────────────────────────────────────────────────
        configuration.preferences.isElementFullscreenEnabled  = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback            = true

        // ── Credential / Password autofill ───────────────────────────────────
        configuration.preferences.setValue(true, forKey: "loadsImagesAutomatically")

        // ── User Scripts ──────────────────────────────────────────────────────
        let ucc = WKUserContentController()

        // Script 1: 100ms interval YouTube pre-roll skipper (documentStart)
        let skipperSource = """
        (function(){
            'use strict';
            function skip(){
                try{
                    var p=document.querySelector('.html5-video-player');
                    var v=document.querySelector('video');
                    if(p&&p.classList.contains('ad-showing')){
                        if(v&&!isNaN(v.duration)&&v.duration>0) v.currentTime=v.duration;
                        var b=document.querySelector('.ytp-skip-ad-button,.ytp-ad-skip-button,.ytp-ad-skip-button-modern');
                        if(b) b.click();
                    }
                    document.querySelectorAll(
                        '.ytp-ad-overlay-container,ytd-ad-slot-renderer,' +
                        '.ytp-ad-text-overlay,.ytp-ad-module,#masthead-ad,' +
                        'ytd-banner-promo-renderer,ytd-promoted-video-renderer'
                    ).forEach(function(el){ if(el.tagName!=='VIDEO') el.remove(); });
                }catch(e){}
            }
            setInterval(skip,100);
        })();
        """

        // Script 2: MutationObserver DOM purge (documentEnd)
        let purgeSource = """
        (function(){
            'use strict';
            var SELECTORS=[
                'ytd-ad-slot-renderer','ytd-action-companion-ad-renderer',
                'ytd-promoted-sparkles-web-renderer','ytd-promoted-video-renderer',
                'ytd-display-ad-renderer','.ytp-ad-overlay-container',
                '.ytp-ad-text-overlay','.ytp-ad-module','#masthead-ad',
                'ytd-banner-promo-renderer','.ad-showing .ytp-ad-player-overlay'
            ];
            function purge(){
                SELECTORS.forEach(function(s){
                    document.querySelectorAll(s).forEach(function(el){
                        if(el.tagName!=='VIDEO') el.remove();
                    });
                });
            }
            purge();
            new MutationObserver(purge).observe(document.body||document.documentElement,
                {childList:true,subtree:true});
        })();
        """

        // Script 3 (Task 4): Universal Cosmetic Injection (atDocumentStart across all frames)
        let cosmeticCSS = """
        ins.adsbygoogle, div[id^='google_ads_iframe'], div[aria-label='Ads'],
        .ad-container, .advertisement, .taboola-container, .outbrain_widget,
        [class*='ad-banner'], [id*='ad-slot'], .ad_unit, .ad-unit, .adsbox,
        .ad-slot, .ad_slot, #ad-leaderboard, .ad-zone, #leaderboard, .banner-ad,
        .adbox, .ad-wrapper, [data-ad], [data-ad-unit], [data-google-query-id],
        .OUTBRAIN, #outbrain, #taboola {
            display: none !important;
            visibility: hidden !important;
            height: 0 !important;
            pointer-events: none !important;
        }
        """
        let cosmeticScriptSource = """
        (function() {
            function inject() {
                if (document.getElementById('maalumi-cosmetic-style')) return;
                var target = document.head || document.documentElement;
                if (!target) return;
                var el = document.createElement('style');
                el.id = 'maalumi-cosmetic-style';
                el.textContent = `\(cosmeticCSS)`;
                target.appendChild(el);
            }
            inject();
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', inject);
            }
        })();
        """

        ucc.addUserScript(WKUserScript(source: skipperSource, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        ucc.addUserScript(WKUserScript(source: purgeSource,   injectionTime: .atDocumentEnd,   forMainFrameOnly: false))
        ucc.addUserScript(WKUserScript(source: cosmeticScriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false))

        // ── Task 3: Tab Propagation ──────────────────────────────────────────
        // Explicitly iterate through compiled rule lists and attach before instantiating WKWebView
        let shieldsOn = UserDefaults.standard.object(forKey: "kShieldsAdBlockEnabled") as? Bool ?? true
        if shieldsOn && LumiShieldsCore.shared.areRulesReady {
            for (index, ruleList) in LumiShieldsCore.shared.compiledRuleLists.enumerated() {
                ucc.add(ruleList)
                print("✅ [LumiShields-Mac] Attached heavy chunk \(index) (\(ruleList.identifier ?? "chunk"))")
            }
            self.areShieldsActive = true
        }

        configuration.userContentController = ucc

        // ── WebView: ClickThroughWebView so toolbar responds on first click ──
        let webView = ClickThroughWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView.allowsBackForwardNavigationGestures = true

        self.webView = webView
        setupKVO()
        observeShieldsToggle()
        LumiShieldsCore.shared.register(webView)

        // If rules are still compiling on first launch, attach when ready
        if shieldsOn && !areShieldsActive {
            LumiShieldsCore.shared.attachRules(to: ucc) { [weak self] in
                guard let self else { return }
                self.onRulesAttached()
            }
        }
    }

    // MARK: - AdBlock Rule Attachment & Toggling

    private func onRulesAttached() {
        areShieldsActive = true
        if let pending = pendingRequest {
            pendingRequest = nil
            print("🚀 [WebViewModel] Executing buffered navigation for \(pending.url?.host ?? "") now that LumiShields is active")
            webView.load(pending)
        }
    }

    /// Observe UserDefaults so toggling the LumiShields master switch takes effect immediately.
    private func observeShieldsToggle() {
        defaultsToken = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let on = UserDefaults.standard.object(forKey: "kShieldsAdBlockEnabled") as? Bool ?? true
            Task { @MainActor in self.setAdBlock(enabled: on) }
        }
    }

    func setAdBlock(enabled: Bool) {
        let ucc = webView.configuration.userContentController
        ucc.removeAllContentRuleLists()

        if enabled {
            LumiShieldsCore.shared.attachRules(to: ucc) { [weak self] in
                guard let self else { return }
                let currentOn = UserDefaults.standard.object(forKey: "kShieldsAdBlockEnabled") as? Bool ?? true
                if currentOn {
                    self.onRulesAttached()
                }
            }
        } else {
            areShieldsActive = false
        }
    }

    // MARK: - Navigation State Sync

    func syncNavigationState() {
        if self.canGoBack != webView.canGoBack {
            self.canGoBack = webView.canGoBack
        }
        if self.canGoForward != webView.canGoForward {
            self.canGoForward = webView.canGoForward
        }
        if self.isLoading != webView.isLoading {
            self.isLoading = webView.isLoading
        }
        if let url = webView.url?.absoluteString, !url.isEmpty, url != "about:blank", self.urlString != url {
            self.urlString = url
        }
        if let title = webView.title, !title.isEmpty, self.pageTitle != title {
            self.pageTitle = title
        }
    }

    // MARK: - KVO

    private func setupKVO() {
        urlObservation = webView.observe(\.url, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.syncNavigationState() }
        }
        canGoBackObservation = webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.syncNavigationState() }
        }
        canGoForwardObservation = webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.syncNavigationState() }
        }
        titleObservation = webView.observe(\.title, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.syncNavigationState() }
        }
        isLoadingObservation = webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.syncNavigationState() }
        }
    }

    // MARK: - Navigation

    func resolveURL(from input: String, defaultEngine: String = "DuckDuckGo") -> URL? {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t != "m:config" else { return nil }
        if t.contains(" ") || !t.contains(".") {
            let enc = t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            switch defaultEngine {
            case "Brave Search": return URL(string: "https://search.brave.com/search?q=\(enc)")
            case "Google":       return URL(string: "https://www.google.com/search?q=\(enc)")
            case "Bing":         return URL(string: "https://www.bing.com/search?q=\(enc)")
            case "Ecosia":       return URL(string: "https://www.ecosia.org/search?q=\(enc)")
            default:             return URL(string: "https://duckduckgo.com/?q=\(enc)")
            }
        } else if t.hasPrefix("http://") || t.hasPrefix("https://") {
            return URL(string: t)
        } else {
            return URL(string: "https://\(t)")
        }
    }

    func load(urlString input: String, defaultEngine: String = "DuckDuckGo") {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if t == "m:config" { self.urlString = "m:config"; return }
        guard let url = resolveURL(from: t, defaultEngine: defaultEngine) else { return }
        self.urlString = url.absoluteString
        let request = URLRequest(url: url)

        let shieldsOn = UserDefaults.standard.object(forKey: "kShieldsAdBlockEnabled") as? Bool ?? true
        if shieldsOn && !areShieldsActive {
            // Task 2: Buffer request until LumiShields rules are attached
            pendingRequest = request
            print("⏳ [WebViewModel] Buffering navigation for \(url.host ?? url.absoluteString) until LumiShields rules are attached")
        } else {
            if webView.url?.absoluteString != url.absoluteString {
                webView.load(request)
            }
        }
    }

    @discardableResult
    func goBack() -> WKNavigation? {
        guard webView.canGoBack else { return nil }
        let nav = webView.goBack()
        syncNavigationState()
        return nav
    }

    @discardableResult
    func goForward() -> WKNavigation? {
        guard webView.canGoForward else { return nil }
        let nav = webView.goForward()
        syncNavigationState()
        return nav
    }

    @discardableResult
    func reload() -> WKNavigation? {
        let nav = webView.reload()
        syncNavigationState()
        return nav
    }

    deinit {
        if let token = defaultsToken {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
