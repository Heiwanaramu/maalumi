import SwiftUI
import AppKit
import MaalumiCore

// MARK: - Menu Notifications

extension Notification.Name {
    static let menuNewTab         = Notification.Name("com.maalumi.menu.newTab")
    static let menuNewWindow      = Notification.Name("com.maalumi.menu.newWindow")
    static let menuCloseTab       = Notification.Name("com.maalumi.menu.closeTab")
    static let menuBack           = Notification.Name("com.maalumi.menu.back")
    static let menuForward        = Notification.Name("com.maalumi.menu.forward")
    static let menuReload         = Notification.Name("com.maalumi.menu.reload")
    static let menuFocusAddress   = Notification.Name("com.maalumi.menu.focusAddress")
    static let menuShowHistory    = Notification.Name("com.maalumi.menu.showHistory")
    static let menuShowBookmarks  = Notification.Name("com.maalumi.menu.showBookmarks")
    static let menuAddBookmark    = Notification.Name("com.maalumi.menu.addBookmark")
    static let menuClearHistory   = Notification.Name("com.maalumi.menu.clearHistory")
    static let menuShowSettings   = Notification.Name("com.maalumi.menu.showSettings")
    static let menuActualSize     = Notification.Name("com.maalumi.menu.actualSize")
    static let menuZoomIn         = Notification.Name("com.maalumi.menu.zoomIn")
    static let menuZoomOut        = Notification.Name("com.maalumi.menu.zoomOut")
}

// MARK: - Window Accessor
// Embeds an NSView to get a reference to the host NSWindow, then configures it
// for Safari-style content-in-titlebar layout (fullSizeContentView).

struct WindowAccessor: NSViewRepresentable {

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.configureWindow(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator: NSObject {
        private var observation: NSObjectProtocol?

        deinit {
            if let observation { NotificationCenter.default.removeObserver(observation) }
        }

        func configureWindow(_ window: NSWindow) {
            applyTitlebarStyle(window)

            // Re-apply after exiting fullscreen so the titlebar doesn't revert to opaque
            observation = NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window, queue: .main
            ) { [weak self] note in
                guard let window = note.object as? NSWindow else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.applyTitlebarStyle(window)
                }
            }
        }

        private func applyTitlebarStyle(_ window: NSWindow) {
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility            = .hidden
            window.isMovableByWindowBackground = true
            window.toolbar = nil

            // Chromeless Immersive Mode — completely remove traffic lights
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        }
    }
}

// MARK: - App

@main
struct Maalumi: App {
    @StateObject private var historyManager  = HistoryManager.shared
    @StateObject private var bookmarkManager = BookmarkManager.shared

    init() {
        // Pre-compile adblock rules immediately at launch
        LumiShieldsCore.shared.precompile()

        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(historyManager)
                .environmentObject(bookmarkManager)
                .background(WindowAccessor())   // sets fullSizeContentView + transparent titlebar
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            // ── File ──────────────────────────────────────────────────────────
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { post(.menuNewTab) }
                    .keyboardShortcut("t", modifiers: .command)

                Button("New Window") { post(.menuNewWindow) }
                    .keyboardShortcut("n", modifiers: .command)

                Divider()

                Button("Close Tab") { post(.menuCloseTab) }
                    .keyboardShortcut("w", modifiers: .command)
            }

            // ── View ──────────────────────────────────────────────────────────
            CommandGroup(replacing: .toolbar) {
                Button("Reload Page") { post(.menuReload) }
                    .keyboardShortcut("r", modifiers: .command)

                Button("Open Location…") { post(.menuFocusAddress) }
                    .keyboardShortcut("l", modifiers: .command)

                Divider()

                Button("Actual Size")  { post(.menuActualSize) }
                    .keyboardShortcut("0", modifiers: .command)
                Button("Zoom In")      { post(.menuZoomIn) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out")     { post(.menuZoomOut) }
                    .keyboardShortcut("-", modifiers: .command)
            }

            // ── History ───────────────────────────────────────────────────────
            CommandMenu("History") {
                Button("Back")    { post(.menuBack)    }.keyboardShortcut("[", modifiers: .command)
                Button("Forward") { post(.menuForward) }.keyboardShortcut("]", modifiers: .command)

                Divider()

                Button("Show History") { post(.menuShowHistory) }
                    .keyboardShortcut("y", modifiers: .command)

                Button("Clear History…") { post(.menuClearHistory) }
            }

            // ── Bookmarks ─────────────────────────────────────────────────────
            CommandMenu("Bookmarks") {
                Button("Add Bookmark…") { post(.menuAddBookmark) }
                    .keyboardShortcut("d", modifiers: .command)

                Button("Show Bookmarks") { post(.menuShowBookmarks) }
                    .keyboardShortcut("b", modifiers: [.command, .shift])

                Divider()

                if bookmarkManager.bookmarks.isEmpty {
                    Text("No Bookmarks").foregroundColor(.secondary)
                } else {
                    ForEach(bookmarkManager.bookmarks.prefix(10)) { bm in
                        Button(bm.title) {
                            NotificationCenter.default.post(
                                name: .openSettingsOnPage, object: bm.url
                            )
                        }
                    }
                }
            }

            // ── Window ────────────────────────────────────────────────────────
            CommandGroup(replacing: .windowArrangement) {
                Button("Select Next Tab")     { post(.init("com.maalumi.cycleForward"))  }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Select Previous Tab") { post(.init("com.maalumi.cycleBackward")) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
            }

            // ── Help ──────────────────────────────────────────────────────────
            CommandGroup(replacing: .help) {
                Link("Maalumi Help", destination: URL(string: "https://duckduckgo.com/?q=maalumi+browser")!)
                Link("Report an Issue", destination: URL(string: "https://github.com")!)
            }
        }

        Settings {
            MaalumiSettingsView()
                .frame(minWidth: 600, idealWidth: 750, maxWidth: .infinity,
                       minHeight: 450, idealHeight: 550, maxHeight: .infinity)
        }
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}
