import SwiftUI
import MaalumiCore

// MARK: - Root Settings Panel

struct MaalumiSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var initialPage: String = "shields"
    @State private var selectedPage: String = "shields"

    var body: some View {
        TabView(selection: $selectedPage) {
            ShieldsPrivacyContent().tabItem { Label("Shields", systemImage: "checkmark.shield") }.tag("shields")
            FilterListsView().tabItem { Label("Filters", systemImage: "line.3.horizontal.decrease") }.tag("filters")
            SearchEnginesContent().tabItem { Label("Search", systemImage: "magnifyingglass") }.tag("search")
            AppearanceContent().tabItem { Label("Appearance", systemImage: "paintpalette") }.tag("appearance")
            NewTabContent().tabItem { Label("New Tab", systemImage: "square.grid.2x2") }.tag("newTab")
            MediaContent().tabItem { Label("Media", systemImage: "play.circle") }.tag("media")
            AdvancedContent().tabItem { Label("Advanced", systemImage: "gearshape.2") }.tag("advanced")
            AboutContent().tabItem { Label("About", systemImage: "info.circle") }.tag("about")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .onAppear {
            selectedPage = initialPage
        }
    }
}

// MARK: - Reusable Components

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Section(title) {
            content()
        }
    }
}

private struct ToggleRow: View {
    let label: String
    let description: String?
    @Binding var value: Bool

    init(_ label: String, description: String? = nil, value: Binding<Bool>) {
        self.label       = label
        self.description = description
        self._value      = value
    }

    var body: some View {
        Toggle(isOn: $value) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if let desc = description {
                    Text(desc).font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Page Content Views

private struct ShieldsPrivacyContent: View {
    @AppStorage("kShieldsAdBlockEnabled")              private var adBlock:             Bool = true
    @AppStorage("kBlockScripts")                       private var blockScripts:        Bool = true
    @AppStorage("kHTTPSOnlyMode")                      private var httpsOnly:           Bool = true
    @AppStorage("kAutoRedirectAMP")                    private var redirectAMP:         Bool = true
    @AppStorage("kAutoRedirectTracking")               private var redirectTracking:    Bool = true
    @AppStorage("kPreventLanguageFingerprinting")      private var preventFingerprint:  Bool = true
    @AppStorage("kSendDNT")                            private var sendDNT:             Bool = true
    @AppStorage("kExperimentalCanvasProtection")       private var canvasProtect:       Bool = true
    @AppStorage("kExperimentalWebRTCBlock")            private var webRTCBlock:         Bool = false

    var body: some View {
        Form {
            SettingsSection(title: "LumiShields Core") {
                ToggleRow("Block Trackers & Ads", description: "Uses Brave's adblock engine", value: $adBlock)
                ToggleRow("Block Scripts", description: "May break some sites", value: $blockScripts)
                ToggleRow("HTTPS-Only Mode", value: $httpsOnly)
            }

            SettingsSection(title: "Privacy") {
                ToggleRow("Auto-redirect AMP pages", value: $redirectAMP)
                ToggleRow("Auto-redirect tracking URLs", value: $redirectTracking)
                ToggleRow("Prevent language fingerprinting", value: $preventFingerprint)
                ToggleRow("Send 'Do Not Track' header", value: $sendDNT)
            }

            SettingsSection(title: "Experimental") {
                ToggleRow("Canvas Fingerprinting Protection", value: $canvasProtect)
                ToggleRow("Strict WebRTC IP Leak Prevention", value: $webRTCBlock)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private struct SearchEnginesContent: View {
    @AppStorage("defaultSearchEngine") private var engine: String = "DuckDuckGo"
    @AppStorage("privateSearchEngine") private var privateEngine: String = "DuckDuckGo"

    let engines = ["DuckDuckGo", "Google", "Brave", "Ecosia", "Startpage", "Bing"]

    var body: some View {
        Form {
            SettingsSection(title: "Search Engines") {
                Picker("Standard Window", selection: $engine) {
                    ForEach(engines, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
                
                Picker("Private Window", selection: $privateEngine) {
                    ForEach(engines, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private struct AppearanceContent: View {
    @AppStorage("kAppTheme") private var theme: String = "system"
    @AppStorage("kShowFavoritesBar") private var favBar: Bool = true
    @AppStorage("kShowTabPreviews") private var previews: Bool = true
    @AppStorage("kCompactTopBar") private var compact: Bool = true

    var body: some View {
        Form {
            SettingsSection(title: "Theme") {
                Picker("Appearance", selection: $theme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.menu)
            }

            SettingsSection(title: "Toolbar & Tabs") {
                ToggleRow("Show Favorites Bar", value: $favBar)
                ToggleRow("Show rich tab previews", value: $previews)
                ToggleRow("Compact Top Bar layout", value: $compact)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private struct NewTabContent: View {
    @AppStorage("kNewTabShowWallpaper") private var wallpaper: Bool = true
    @AppStorage("kNewTabShowTopSites") private var topSites: Bool = true
    @AppStorage("kNewTabShowStats") private var stats: Bool = true

    var body: some View {
        Form {
            SettingsSection(title: "New Tab Page") {
                ToggleRow("Show background wallpaper", value: $wallpaper)
                ToggleRow("Show top sites", value: $topSites)
                ToggleRow("Show privacy stats", value: $stats)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private struct MediaContent: View {
    @AppStorage("kBlockAutoplay") private var blockAutoplay: Bool = true
    @AppStorage("kAllowPiP") private var pip: Bool = true

    var body: some View {
        Form {
            SettingsSection(title: "Media Playback") {
                ToggleRow("Block annoying autoplaying media", value: $blockAutoplay)
                ToggleRow("Allow automatic Picture-in-Picture", value: $pip)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private struct AdvancedContent: View {
    @AppStorage("kEnableDevTools") private var devTools: Bool = false
    @AppStorage("kHardwareAcceleration") private var hwAccel: Bool = true
    @AppStorage("kPreloadPages") private var preload: Bool = true

    var body: some View {
        Form {
            SettingsSection(title: "Developer") {
                ToggleRow("Enable Developer Tools", value: $devTools)
            }

            SettingsSection(title: "System") {
                ToggleRow("Use Hardware Acceleration", value: $hwAccel)
                ToggleRow("Preload pages for faster browsing", value: $preload)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private struct AboutContent: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.checkerboard")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            VStack(spacing: 4) {
                Text("Maalumi Browser").font(.title.weight(.bold))
                Text("Version 1.0 (Alpha)").foregroundStyle(.secondary)
            }
            
            VStack(spacing: 2) {
                Text("Built on Brave Core").font(.headline)
                Text("Engine tag: \(BraveEngineVersion.tag)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.1)))

            Text("© 2026 Maalumi Project. All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
    }
}
