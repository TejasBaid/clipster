import AppKit
import ServiceManagement
import ClipsterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let previewMode: Bool
    private var store: ClipStore!
    private var watcher: PasteboardWatcher!
    private var coordinator: Coordinator!
    private var statusItem: NSStatusItem!
    private var permissionPoll: Timer?

    init(previewMode: Bool) {
        self.previewMode = previewMode
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = ClipStore(fileURL: previewMode ? nil : Self.storeURL)
        if previewMode { seedPreviewData() }

        watcher = PasteboardWatcher(store: store)
        watcher.start()
        coordinator = Coordinator(store: store, watcher: watcher)
        setUpStatusItem()

        if previewMode {
            coordinator.showSticky(centered: true)
        } else {
            startTapWhenTrusted()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    private static var storeURL: URL {
        URL.applicationSupportDirectory.appending(path: "Clipster/store.json")
    }

    // MARK: Accessibility

    /// The event tap needs Accessibility access. Prompt once, then poll
    /// quietly until it's granted so the hotkeys start working without a relaunch.
    private func startTapWhenTrusted() {
        let prompt = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if AXIsProcessTrustedWithOptions(prompt), coordinator.startTap() { return }

        permissionPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, AXIsProcessTrusted(), self.coordinator.startTap() else { return }
                self.permissionPoll?.invalidate()
                self.permissionPoll = nil
            }
        }
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Clipster")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !coordinator.isTapRunning {
            menu.addItem(item("Grant Accessibility Access…", #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        }
        for hint in ["Hold ⌘C — save to a slot", "Hold ⌘V — paste from slots & history"] {
            let info = NSMenuItem(title: hint, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        }
        menu.addItem(item("Open Clipster", #selector(openPanel)))
        menu.addItem(.separator())

        let login = item("Open at Login", #selector(toggleLoginItem))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Clear History", #selector(clearHistory)))
        menu.addItem(item("Clear Slots", #selector(clearSlots)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Clipster", #selector(NSApplication.terminate(_:)), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        return item
    }

    @objc private func openPanel() { coordinator.showSticky() }
    @objc private func clearHistory() { store.clearHistory() }
    @objc private func clearSlots() { store.clearSlots() }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Clipster: login item toggle failed: \(error)")
        }
    }

    // MARK: Preview

    private func seedPreviewData() {
        let samples: [(String, String, String)] = [
            ("git commit -m \"feat: glass panel at caret\"", "Terminal", "com.apple.Terminal"),
            ("https://developer.apple.com/documentation/appkit/nsglasseffectview", "Safari", "com.apple.Safari"),
            ("Thanks so much — I'll circle back on Friday with the revised numbers.", "Mail", "com.apple.mail"),
            ("let threshold: Duration = .milliseconds(350)", "Xcode", "com.apple.dt.Xcode"),
            ("#1F6FEB", "Figma", "com.figma.Desktop"),
            ("ssh deploy@10.0.4.12 -p 2222", "Terminal", "com.apple.Terminal"),
            ("Meeting notes: ship v1 of Clipster, then images + plain-text paste", "Notes", "com.apple.Notes"),
        ]
        for (text, app, id) in samples.reversed() { store.add(text, sourceApp: app, sourceBundleID: id) }
        store.assign(store.history[4], toSlot: 1)
        store.assign(store.history[2], toSlot: 2)
        store.assign(store.history[5], toSlot: 4)
        store.assign(store.history[0], toSlot: 7)
    }
}
