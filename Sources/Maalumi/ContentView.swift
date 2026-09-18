import SwiftUI
import AppKit
import Combine
import MaalumiCore

// MARK: - BrowserTab

@MainActor
final class BrowserTab: Identifiable, ObservableObject, Equatable {
    let id = UUID()
    @Published var title: String
    @Published var url:   String
    let viewModel: WebViewModel
    private var cancellables = Set<AnyCancellable>()

    var urlString: String {
        let v = viewModel.urlString
        if !v.isEmpty && v != "about:blank" { return v }
        return url
    }

    init(title: String = "New Tab", url: String = "") {
        self.title = title
        self.url   = url
        let vm = WebViewModel()
        self.viewModel = vm

        vm.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        if !url.isEmpty && url != "m:config" { vm.load(urlString: url) }
    }

    static nonisolated func == (lhs: BrowserTab, rhs: BrowserTab) -> Bool { lhs.id == rhs.id }
}

// MARK: - QuickBookmark

struct QuickBookmark: Identifiable {
    let id = UUID()
    let title: String; let url: String; let iconName: String
}

// MARK: - Navigation Control Subviews

struct NavigationControlGroup: View {
    @ObservedObject var viewModel: WebViewModel

    var body: some View {
        HStack(spacing: 2) {
            Button(action: { viewModel.goBack() }) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back (⌘[)")
            .disabled(!viewModel.canGoBack)

            Button(action: { viewModel.goForward() }) {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Forward (⌘])")
            .disabled(!viewModel.canGoForward)
        }
    }
}

struct ReloadControl: View {
    @ObservedObject var viewModel: WebViewModel

    var body: some View {
        Button(action: {
            if viewModel.isLoading {
                viewModel.webView.stopLoading()
            } else {
                viewModel.reload()
            }
        }) {
            Image(systemName: viewModel.isLoading ? "xmark" : "arrow.clockwise")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(viewModel.isLoading ? "Stop (⌘.)" : "Reload (⌘R)")
    }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject  private var tabManager      = TabManager()
    @EnvironmentObject private var history    : HistoryManager
    @EnvironmentObject private var bookmarks  : BookmarkManager

    @FocusState private var isAddressBarFocused: Bool
    @State private var isTopBarVisible        = false
    @State private var hideTopBarTask: DispatchWorkItem? = nil

    @State private var isShieldsPopoverShown  = false
    @State private var isSiteSettingsShown    = false
    @State private var showTabOverview        = false
    @State private var showHistoryPanel       = false
    @State private var showBookmarksPanel     = false
    @State private var settingsPage: String   = "shields"
    @State private var hoveredTabId: UUID?    = nil
    @State private var showClearHistoryAlert  = false
    @State private var showAddBookmarkSheet   = false
    @State private var newBookmarkTitle       = ""

    @AppStorage("kShieldsAdBlockEnabled") private var isShieldsActive:    Bool   = true
    @AppStorage("defaultSearchEngine")    private var defaultSearchEngine: String = "DuckDuckGo"

    private let quickBookmarks: [QuickBookmark] = [
        QuickBookmark(title: "DuckDuckGo",  url: "https://duckduckgo.com",    iconName: "magnifyingglass"),
        QuickBookmark(title: "Brave Search", url: "https://search.brave.com", iconName: "shield.fill"),
        QuickBookmark(title: "Google",       url: "https://www.google.com",   iconName: "g.circle.fill"),
        QuickBookmark(title: "YouTube",      url: "https://www.youtube.com",  iconName: "play.rectangle.fill"),
        QuickBookmark(title: "GitHub",       url: "https://github.com",       iconName: "terminal.fill"),
        QuickBookmark(title: "Wikipedia",    url: "https://www.wikipedia.org",iconName: "book.fill")
    ]

    // MARK: - Smart Address & Visibility Helpers

    private var actualURL: String {
        tabManager.activeTab?.urlString ?? ""
    }

    private var displayURL: String {
        let actual = actualURL
        guard !actual.isEmpty, actual != "about:blank", actual != "m:config" else { return "" }
        if let url = URL(string: actual), let host = url.host, !host.isEmpty {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return actual
    }

    private var addressBinding: Binding<String> {
        Binding(
            get: {
                if isAddressBarFocused {
                    return tabManager.addressInput
                } else {
                    return displayURL
                }
            },
            set: { newValue in
                tabManager.addressInput = newValue
            }
        )
    }

    private var isBookmarked: Bool {
        bookmarks.isBookmarked(url: actualURL)
    }

    private var shouldShowTopBar: Bool {
        isTopBarVisible || isAddressBarFocused || isShieldsPopoverShown || isSiteSettingsShown || showTabOverview
    }

    private func scheduleHideTopBar() {
        hideTopBarTask?.cancel()
        let task = DispatchWorkItem { [self] in
            if !isAddressBarFocused && !isShieldsPopoverShown && !isSiteSettingsShown && !showTabOverview {
                withAnimation(.spring()) {
                    isTopBarVisible = false
                }
            }
        }
        hideTopBarTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    var body: some View {
        rootLayout
            .alert("Clear Browsing History?", isPresented: $showClearHistoryAlert) {
                Button("Clear", role: .destructive) { history.clear() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will remove all history from Maalumi.")
            }
            .sheet(isPresented: $showAddBookmarkSheet) { addBookmarkSheet }
            .onChange(of: isAddressBarFocused) { focused in
                if focused {
                    hideTopBarTask?.cancel()
                    withAnimation(.spring()) { isTopBarVisible = true }
                    if let active = tabManager.activeTab, !active.urlString.isEmpty {
                        tabManager.addressInput = active.urlString
                    }
                } else {
                    scheduleHideTopBar()
                }
            }
            .onChange(of: tabManager.activeTab?.viewModel.urlString) { newUrl in
                guard let newUrl, !newUrl.isEmpty, newUrl != "m:config" else { return }
                if !isAddressBarFocused {
                    tabManager.addressInput = newUrl
                }
                tabManager.activeTab?.url = newUrl
                if let title = tabManager.activeTab?.title { history.record(url: newUrl, title: title) }
            }
            .onChange(of: tabManager.activeTab?.viewModel.pageTitle) { newTitle in
                guard let newTitle, !newTitle.isEmpty else { return }
                tabManager.activeTab?.title = newTitle
                if let url = tabManager.activeTab?.urlString { history.record(url: url, title: newTitle) }
            }
            .modifier(MenuNotificationHandler(
                tabManager:          tabManager,
                history:             history,
                showHistoryPanel:    $showHistoryPanel,
                showBookmarksPanel:  $showBookmarksPanel,
                showClearHistory:    $showClearHistoryAlert,
                isAddressBarFocused: $isAddressBarFocused,
                isTopBarVisible:     $isTopBarVisible,
                settingsPage:        $settingsPage,
                defaultSearchEngine: defaultSearchEngine
            ))
            .background(
                ZStack {
                    Button("") { tabManager.cycleTab(forward: true)  }.keyboardShortcut(KeyboardShortcut(KeyEquivalent("\t"), modifiers: .option)).hidden()
                    Button("") { tabManager.cycleTab(forward: false) }.keyboardShortcut(KeyboardShortcut(KeyEquivalent("\t"), modifiers: [.option, .shift])).hidden()
                    Button("") { tabManager.cycleTab(forward: true)  }.keyboardShortcut("]", modifiers: [.command, .shift]).hidden()
                    Button("") { tabManager.cycleTab(forward: false) }.keyboardShortcut("[", modifiers: [.command, .shift]).hidden()
                    Button("") {
                        if let id = tabManager.activeTabId as UUID? { tabManager.closeTab(id: id) }
                    }.keyboardShortcut("w", modifiers: .command).hidden()
                }
            )
    }

    // Root layout: Fullscreen canvas with auto-hiding Top Bar overlay
    private var rootLayout: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Fullscreen web canvas
                webContentContainer
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Invisible hover trigger zone at the absolute top 15 pixels
                Color.clear
                    .frame(height: 15)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            hideTopBarTask?.cancel()
                            withAnimation(.spring()) {
                                isTopBarVisible = true
                            }
                        }
                    }

                // Custom Top Bar overlay with spring slide & opacity
                VStack(spacing: 0) {
                    compactTopBar
                    Divider()
                }
                .background(.ultraThinMaterial)
                .offset(y: shouldShowTopBar ? 0 : -80)
                .opacity(shouldShowTopBar ? 1 : 0)
                .animation(.spring(), value: shouldShowTopBar)
                .onHover { hovering in
                    if hovering {
                        hideTopBarTask?.cancel()
                        withAnimation(.spring()) {
                            isTopBarVisible = true
                        }
                    } else {
                        scheduleHideTopBar()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showHistoryPanel {
                Divider()
                historyPanel
                    .frame(width: 280)
                    .transition(.move(edge: .trailing))
            }

            if showBookmarksPanel {
                Divider()
                bookmarksPanel
                    .frame(width: 280)
                    .transition(.move(edge: .trailing))
            }
        }
        .ignoresSafeArea(.all, edges: .top)
        .animation(.easeInOut(duration: 0.2), value: showHistoryPanel)
        .animation(.easeInOut(duration: 0.2), value: showBookmarksPanel)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Top Bar
    // ─────────────────────────────────────────────────────────────────────────

    private var compactTopBar: some View {
        HStack(alignment: .center, spacing: 0) {
            leftActionGroup.padding(.leading, 12).padding(.trailing, 6)

            HStack(spacing: 2) {
                tabStrip

                Button(action: {
                    tabManager.addNewTab()
                    withAnimation(.spring()) { isTopBarVisible = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isAddressBarFocused = true }
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.7))
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("New Tab (⌘T)")
            }

            rightActionGroup.padding(.leading, 6).padding(.trailing, 12)
        }
        .frame(height: 38, alignment: .center)
        .background(.ultraThinMaterial)
    }

    // MARK: Left Actions

    private var leftActionGroup: some View {
        HStack(spacing: 2) {
            if let vm = tabManager.activeTab?.viewModel {
                NavigationControlGroup(viewModel: vm)
            } else {
                toolbarButton("chevron.backward", help: "Back (⌘[)") {}
                    .disabled(true)
                toolbarButton("chevron.forward", help: "Forward (⌘])") {}
                    .disabled(true)
            }

            toolbarButton("arrow.up.left.and.arrow.down.right", help: "Toggle Full Screen") {
                if let window = NSApp.keyWindow {
                    window.toggleFullScreen(nil)
                }
            }

            if let vm = tabManager.activeTab?.viewModel {
                ReloadControl(viewModel: vm)
            } else {
                toolbarButton("arrow.clockwise", help: "Reload (⌘R)") {}
                    .disabled(true)
            }

            // LumiShields
            Button(action: { isShieldsPopoverShown.toggle() }) {
                Image(systemName: isShieldsActive ? "checkmark.shield.fill" : "shield.slash.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isShieldsActive ? Color.blue : Color.secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("LumiShields (Privacy Controls)")
            .popover(isPresented: $isShieldsPopoverShown, arrowEdge: .bottom) {
                LumiShieldsPopoverView(activeDomain: tabManager.currentDomain)
            }
        }
    }

    // MARK: Right Actions

    private var rightActionGroup: some View {
        HStack(spacing: 2) {
            // Bookmark
            Button(action: {
                guard let active = tabManager.activeTab,
                      !active.urlString.isEmpty,
                      active.urlString != "about:blank" else { return }
                if isBookmarked {
                    bookmarks.toggle(url: active.urlString, title: active.title)
                } else {
                    triggerAddBookmark()
                }
            }) {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isBookmarked ? Color.yellow : Color.primary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isBookmarked ? "Remove Bookmark (⌘D)" : "Add Bookmark (⌘D)")
            .keyboardShortcut("d", modifiers: .command)

            // History
            Button(action: { withAnimation { showHistoryPanel.toggle(); showBookmarksPanel = false } }) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(showHistoryPanel ? Color.accentColor : Color.primary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show History (⌘Y)")

            // Bookmarks panel
            Button(action: { withAnimation { showBookmarksPanel.toggle(); showHistoryPanel = false } }) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(showBookmarksPanel ? Color.accentColor : Color.primary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show Bookmarks (⌘⇧B)")

            // Share — native SwiftUI ShareLink anchors the sheet directly to this button
            shareButton

            // Tab Overview
            Button(action: { showTabOverview.toggle() }) {
                Image(systemName: "square.on.square")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(showTabOverview ? Color.accentColor : Color.primary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Tab Overview")
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if let activeTab = tabManager.activeTab,
           let validURL = URL(string: activeTab.urlString),
           !activeTab.urlString.isEmpty,
           activeTab.urlString != "about:blank" {
            ShareLink(item: validURL) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Share Page")
        } else {
            Button(action: {}) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(true)
            .help("Share Page")
        }
    }

    // MARK: Tab Strip

    private var tabStrip: some View {
        Group {
            if tabManager.tabs.count <= 1 { singleTabBar }
            else                          { multiTabBar  }
        }
    }

    // Single tab — stretches full available center width
    private var singleTabBar: some View {
        HStack(spacing: 5) {
            Image(systemName: isShieldsActive ? "lock.fill" : "globe")
                .font(.system(size: 10))
                .foregroundStyle(isShieldsActive ? Color.blue : Color.secondary)

            AddressBar(
                text: addressBinding,
                placeholder: "Search or enter website",
                isFocused: $isAddressBarFocused,
                textAlignment: .center,
                fontSize: 13,
                onSubmit: {
                    tabManager.submitAddressInput(tabManager.addressInput, defaultEngine: defaultSearchEngine)
                    isAddressBarFocused = false
                }
            )
            .frame(height: 18)

            if let wvURL = tabManager.activeTab?.viewModel.webView.url,
               !wvURL.absoluteString.isEmpty,
               wvURL.absoluteString != "about:blank",
               tabManager.activeTab?.url != "m:config" {
                Button(action: { isSiteSettingsShown.toggle() }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Site Settings")
                .popover(isPresented: $isSiteSettingsShown, arrowEdge: .bottom) {
                    SiteSettingsPopoverView(domain: tabManager.currentDomain)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(
            isAddressBarFocused ? Color.accentColor : Color.gray.opacity(0.3),
            lineWidth: isAddressBarFocused ? 1.5 : 1))
        .padding(.vertical, 4)
    }

    // Multi-tab: strict equal-width (50/50, 33/33/33 etc) — no ScrollView
    private var multiTabBar: some View {
        HStack(spacing: 4) {
            ForEach(tabManager.tabs) { tab in
                if tab.id == tabManager.activeTabId {
                    activeMultiTabTile(tab: tab)
                } else {
                    inactiveTabTile(tab: tab)
                }
            }
        }
        .frame(maxWidth: .infinity)   // span all available center space
        .padding(.vertical, 4)
    }

    private func activeMultiTabTile(tab: BrowserTab) -> some View {
        HStack(spacing: 5) {
            Image(systemName: isShieldsActive ? "lock.fill" : "globe")
                .font(.system(size: 10))
                .foregroundStyle(isShieldsActive ? Color.blue : Color.secondary)

            AddressBar(
                text: addressBinding,
                placeholder: "Search or enter website",
                isFocused: $isAddressBarFocused,
                textAlignment: .leading,
                fontSize: 12,
                onSubmit: {
                    tabManager.submitAddressInput(tabManager.addressInput, defaultEngine: defaultSearchEngine)
                    isAddressBarFocused = false
                }
            )
            .frame(height: 18)

            Button(action: { tabManager.closeTab(id: tab.id) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.secondary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)   // forces equal width split with siblings
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(NSColor.controlBackgroundColor))   // active = filled
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isAddressBarFocused ? Color.accentColor : Color.gray.opacity(0.25),
                        lineWidth: isAddressBarFocused ? 1.5 : 1)
        )
    }

    private func inactiveTabTile(tab: BrowserTab) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "globe")
                .font(.system(size: 10))
                .foregroundStyle(Color.secondary)
            Text(tab.title.isEmpty ? "New Tab" : tab.title)
                .font(.system(size: 11))
                .foregroundStyle(Color.primary.opacity(0.6))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(action: { tabManager.closeTab(id: tab.id) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hoveredTabId == tab.id ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)   // ← forces equal split with active tile
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.clear)   // inactive = transparent
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.gray.opacity(hoveredTabId == tab.id ? 0.3 : 0.15), lineWidth: 1)
        )
        .onHover { hoveredTabId = $0 ? tab.id : nil }
        .onTapGesture { tabManager.selectTab(id: tab.id); isAddressBarFocused = false }
    }

    // MARK: Toolbar Button Helper

    @ViewBuilder
    private func toolbarButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())   // full 26×26 area responds to clicks
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Web Content Container
    // ─────────────────────────────────────────────────────────────────────────

    private var webContentContainer: some View {
        ZStack {
            if showTabOverview {
                tabOverviewGrid
            } else if tabManager.addressInput.trimmingCharacters(in: .whitespaces) == "m:config" {
                MaalumiConfigView()
            } else {
                // ── Keep ALL WebViews alive simultaneously ──────────────────
                // Destroying/recreating on tab switch loses page state and causes
                // the "won't navigate from second tab" bug. The ZStack keeps every
                // WKWebView in the hierarchy; only the active one is visible.
                ForEach(tabManager.tabs) { tab in
                    MaalumiWebView(viewModel: tab.viewModel)
                        .opacity(tab.id == tabManager.activeTabId ? 1 : 0)
                        .allowsHitTesting(tab.id == tabManager.activeTabId)
                }

                // Landing page overlays the active tab only when it has no URL
                if let active = tabManager.activeTab,
                   (active.url.isEmpty || active.url == "about:blank") {
                    landingPageView
                }
            }
        }
    }


    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Side Panels
    // ─────────────────────────────────────────────────────────────────────────

    private var historyPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("History", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: { showClearHistoryAlert = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear History")

                Button(action: { withAnimation { showHistoryPanel = false } }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider()

            if history.items.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "clock").font(.system(size: 32)).foregroundStyle(Color.secondary)
                    Text("No History").font(.subheadline).foregroundStyle(Color.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        ForEach(history.groupedByDay, id: \.label) { group in
                            Section {
                                ForEach(group.items) { item in
                                    historyRow(item: item)
                                }
                            } header: {
                                Text(group.label)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.secondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(NSColor.windowBackgroundColor))
                            }
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func historyRow(item: HistoryItem) -> some View {
        Button(action: {
            tabManager.submitAddressInput(item.url, defaultEngine: defaultSearchEngine)
        }) {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title.isEmpty ? item.url : item.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(Color.primary)
                    Text(item.url)
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: { history.remove(id: item.id) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .opacity(0.5)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(NSColor.windowBackgroundColor))
        Divider().padding(.leading, 40)
    }

    private var bookmarksPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Bookmarks", systemImage: "books.vertical.fill")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: { triggerAddBookmark() }) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Add Bookmark")

                Button(action: { withAnimation { showBookmarksPanel = false } }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider()

            if bookmarks.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "bookmark.slash").font(.system(size: 32)).foregroundStyle(Color.secondary)
                    Text("No Bookmarks").font(.subheadline).foregroundStyle(Color.secondary)
                    Button("Add Current Page") { triggerAddBookmark() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(bookmarks.bookmarks) { bm in
                            bookmarkRow(bm: bm)
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func bookmarkRow(bm: Bookmark) -> some View {
        Button(action: {
            tabManager.submitAddressInput(bm.url, defaultEngine: defaultSearchEngine)
        }) {
            HStack(spacing: 10) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.yellow)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(bm.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(Color.primary)
                    Text(bm.url)
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: { bookmarks.remove(id: bm.id) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .opacity(0.5)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Divider().padding(.leading, 40)
    }

    // MARK: Add Bookmark Sheet

    private var addBookmarkSheet: some View {
        VStack(spacing: 20) {
            Text("Add Bookmark")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Title").font(.caption).foregroundStyle(Color.secondary)
                TextField("Bookmark title", text: $newBookmarkTitle)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("URL").font(.caption).foregroundStyle(Color.secondary)
                Text(tabManager.activeTab?.urlString ?? "")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
            }

            HStack {
                Button("Cancel") { showAddBookmarkSheet = false }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Add") {
                    guard let active = tabManager.activeTab else { return }
                    let urlToSave = active.urlString
                    guard !urlToSave.isEmpty, urlToSave != "about:blank" else { return }
                    let title = newBookmarkTitle.isEmpty ? (active.title.isEmpty ? urlToSave : active.title) : newBookmarkTitle
                    bookmarks.toggle(url: urlToSave, title: title)
                    showAddBookmarkSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled((tabManager.activeTab?.urlString ?? "").isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Landing Page
    // ─────────────────────────────────────────────────────────────────────────

    private var landingPageView: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Image(systemName: "shield.checkerboard")
                    .font(.system(size: 52))
                    .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
                Text("Maalumi").font(.largeTitle).fontWeight(.bold)
                Text("Privacy-first browsing, powered by LumiShields.")
                    .font(.subheadline).foregroundStyle(Color.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 16)], spacing: 16) {
                ForEach(quickBookmarks) { bm in
                    Button(action: { tabManager.submitAddressInput(bm.url, defaultEngine: defaultSearchEngine) }) {
                        VStack(spacing: 10) {
                            Image(systemName: bm.iconName)
                                .font(.system(size: 24))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 48, height: 48)
                                .background(Circle().fill(Color(NSColor.controlBackgroundColor))
                                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2))
                            Text(bm.title).font(.caption).fontWeight(.medium)
                                .foregroundStyle(Color.primary).lineLimit(1)
                        }
                        .frame(width: 110, height: 90)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.15), lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 32).frame(maxWidth: 600)

            // Recent history on start page
            if !history.items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Recent", systemImage: "clock").font(.caption).foregroundStyle(Color.secondary)
                    ForEach(history.items.prefix(5)) { item in
                        Button(action: { tabManager.submitAddressInput(item.url, defaultEngine: defaultSearchEngine) }) {
                            HStack(spacing: 8) {
                                Image(systemName: "clock").font(.caption2).foregroundStyle(Color.secondary)
                                Text(item.title.isEmpty ? item.url : item.title)
                                    .font(.caption).lineLimit(1).foregroundStyle(Color.secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 400)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.underPageBackgroundColor))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Tab Overview Grid
    // ─────────────────────────────────────────────────────────────────────────

    private var tabOverviewGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Open Tabs (\(tabManager.tabs.count))").font(.title2).fontWeight(.bold)
                Spacer()
                Button(action: { tabManager.addNewTab(); showTabOverview = false;
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isAddressBarFocused = true }
                }) { Label("New Tab", systemImage: "plus") }.buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24).padding(.top, 24)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)], spacing: 16) {
                    ForEach(tabManager.tabs) { tab in tabCard(tab: tab) }
                }.padding(24)
            }
        }
        .padding(.top, 50)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.underPageBackgroundColor))
    }

    private func tabCard(tab: BrowserTab) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "globe").font(.system(size: 12)).foregroundStyle(Color.secondary)
                Text(tab.title.isEmpty ? "New Tab" : tab.title)
                    .font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer()
                Button(action: {
                    tabManager.closeTab(id: tab.id)
                    // If no tabs left, exit overview
                    if tabManager.tabs.isEmpty { showTabOverview = false }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close Tab")
            }
            Rectangle()
                .fill(tab.id == tabManager.activeTabId ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                .frame(height: 120).cornerRadius(6)
                .overlay(VStack(spacing: 6) {
                    Image(systemName: "shield.checkerboard").font(.title).foregroundStyle(Color.accentColor.opacity(0.8))
                    Text(tab.url.isEmpty ? "New Tab" : tabManager.extractDomain(from: tab.url))
                        .font(.caption).foregroundStyle(Color.secondary)
                })
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(tab.id == tabManager.activeTabId ? Color.accentColor : Color.gray.opacity(0.2),
                    lineWidth: tab.id == tabManager.activeTabId ? 2 : 1))
        .onTapGesture { tabManager.selectTab(id: tab.id); showTabOverview = false }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private func triggerAddBookmark() {
        guard let active = tabManager.activeTab,
              !active.urlString.isEmpty,
              active.urlString != "about:blank" else { return }
        newBookmarkTitle = active.title.isEmpty ? active.urlString : active.title
        showAddBookmarkSheet = true
    }

}

// MARK: - TabManager

@MainActor
final class TabManager: ObservableObject {
    @Published var tabs:         [BrowserTab] = []
    @Published var activeTabId:  UUID         = UUID()
    @Published var addressInput: String       = ""
    private var activeTabCancellable: AnyCancellable?

    init() {
        let tab     = BrowserTab(title: "New Tab", url: "")
        tabs        = [tab]
        activeTabId = tab.id
        bindActiveTab()
    }

    private func bindActiveTab() {
        activeTabCancellable = activeTab?.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var activeTab: BrowserTab? { tabs.first(where: { $0.id == activeTabId }) }

    var currentDomain: String {
        let raw = activeTab?.urlString ?? addressInput
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "m:config" else { return trimmed }
        let full = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: full), let host = url.host else { return trimmed }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    func addNewTab() {
        let tab = BrowserTab(title: "New Tab", url: "")
        tabs.append(tab); selectTab(id: tab.id)
    }

    func closeTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: idx)
        if tabs.isEmpty { addNewTab() }
        else { selectTab(id: tabs[min(idx, tabs.count - 1)].id) }
    }



    func submitAddressInput(_ rawInput: String, defaultEngine: String) {
        let t = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if t == "m:config" {
            addressInput = "m:config"
            activeTab?.url   = "m:config"
            activeTab?.title = "Internal Config"
            objectWillChange.send()
            return
        }
        guard let tab = activeTab else { return }
        tab.viewModel.load(urlString: t, defaultEngine: defaultEngine)
        tab.url      = tab.viewModel.urlString
        tab.title    = extractDomain(from: tab.viewModel.urlString)
        addressInput = tab.viewModel.urlString
        objectWillChange.send() // ensure ContentView re-renders to show this tab's WebView
    }

    func selectTab(id: UUID) {
        activeTabId  = id
        let selectedTab = tabs.first(where: { $0.id == id })
        addressInput = selectedTab?.urlString ?? ""
        bindActiveTab()
        objectWillChange.send()
    }

    func extractDomain(from urlString: String) -> String {
        let full = urlString.contains("://") ? urlString : "https://\(urlString)"
        guard let url = URL(string: full), let host = url.host else { return urlString }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    func cycleTab(forward: Bool) {
        guard tabs.count > 1,
              let idx = tabs.firstIndex(where: { $0.id == activeTabId }) else { return }
        selectTab(id: tabs[forward ? (idx + 1) % tabs.count : (idx - 1 + tabs.count) % tabs.count].id)
    }
}

// MARK: - Menu Notification Handler ViewModifier
// Separating all onReceive calls into a ViewModifier prevents the Swift
// type-checker from timing out on the monolithic body expression.

struct MenuNotificationHandler: ViewModifier {
    let tabManager:          TabManager
    let history:             HistoryManager
    @Binding var showHistoryPanel:    Bool
    @Binding var showBookmarksPanel:  Bool
    @Binding var showClearHistory:    Bool
    @FocusState.Binding var isAddressBarFocused: Bool
    @Binding var isTopBarVisible:     Bool
    @Binding var settingsPage:        String
    let defaultSearchEngine: String

    func body(content: Content) -> some View {
        let v1 = content
            .onReceive(NotificationCenter.default.publisher(for: .menuNewTab)) { _ in
                tabManager.addNewTab()
                withAnimation(.spring()) { isTopBarVisible = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isAddressBarFocused = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .menuCloseTab)) { _ in
                if let id = tabManager.activeTabId as UUID? { tabManager.closeTab(id: id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .menuBack)) { _ in
                _ = tabManager.activeTab?.viewModel.goBack()
            }
            .onReceive(NotificationCenter.default.publisher(for: .menuForward)) { _ in
                _ = tabManager.activeTab?.viewModel.goForward()
            }
            .onReceive(NotificationCenter.default.publisher(for: .menuReload)) { _ in
                _ = tabManager.activeTab?.viewModel.reload()
            }

        let v2 = v1
            .onReceive(NotificationCenter.default.publisher(for: .menuFocusAddress)) { _ in
                withAnimation(.spring()) { isTopBarVisible = true }
                isAddressBarFocused = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .menuShowHistory)) { _ in
                withAnimation { showHistoryPanel.toggle(); showBookmarksPanel = false }
            }
            .onReceive(NotificationCenter.default.publisher(for: .menuShowBookmarks)) { _ in
                withAnimation { showBookmarksPanel.toggle(); showHistoryPanel = false }
            }
            .onReceive(NotificationCenter.default.publisher(for: .menuAddBookmark)) { _ in
                NotificationCenter.default.post(name: .init("com.maalumi.doAddBookmark"), object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: .menuClearHistory)) { _ in
                showClearHistory = true
            }

        return v2
            .onReceive(NotificationCenter.default.publisher(for: .menuShowSettings)) { _ in
                // Open the native macOS Settings window (same as ⌘,)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: .menuZoomIn)) { _ in
                tabManager.activeTab?.viewModel.webView.pageZoom += 0.1
            }
            .onReceive(NotificationCenter.default.publisher(for: .menuZoomOut)) { _ in
                tabManager.activeTab?.viewModel.webView.pageZoom -= 0.1
            }
            .onReceive(NotificationCenter.default.publisher(for: .menuActualSize)) { _ in
                tabManager.activeTab?.viewModel.webView.pageZoom = 1.0
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsOnPage)) { note in
                if let page = note.object as? String {
                    if page.hasPrefix("http") {
                        tabManager.submitAddressInput(page, defaultEngine: defaultSearchEngine)
                    } else {
                        settingsPage = page
                        // Open the native macOS Settings window
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                }
            }
    }
}
