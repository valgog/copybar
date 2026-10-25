import AppKit
import CopyBarCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let config = ConfigFile()
    private var store: HistoryStore!
    private var watcher: ClipboardWatcher!
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var hotKey: HotKey?
    private var askedForAccessibility = false
    private var settings: Settings { config.settings }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = HistoryStore(maxItems: settings.maxItems)
        watcher = ClipboardWatcher(store: store, settings: settings)
        watcher.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "CopyBar")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        registerHotKey()
        LoginItem.set(settings.launchAtLogin)

        config.onChange = { [weak self] _ in self?.applySettings() }
        config.startWatching()
    }

    private func applySettings() {
        let old = watcher.settings
        watcher.settings = settings
        if old.pollInterval != settings.pollInterval { watcher.start() }
        store.maxItems = settings.maxItems
        if old.hotkey != settings.hotkey { registerHotKey() }
        if old.launchAtLogin != settings.launchAtLogin { LoginItem.set(settings.launchAtLogin) }
    }

    private func registerHotKey() {
        hotKey = nil
        guard let string = settings.hotkey, let spec = HotKeySpec.parse(string) else { return }
        hotKey = HotKey(spec) { [weak self] in self?.showMenuFromHotKey() }
        if hotKey == nil {
            log.error("Could not register hotkey \(string, privacy: .public); another app may be using it")
        }
    }

    /// Opens the menu just below the text cursor when there is one, and
    /// otherwise under the menu bar icon, as if it had been clicked.
    /// CopyBar is deliberately not activated: activation completes
    /// asynchronously and would close the menu right after it opens. The
    /// menu gets mouse and keyboard input anyway, and the app you were in
    /// keeps focus for ⌘V.
    private func showMenuFromHotKey() {
        // Ask for Accessibility access once per launch; without it there
        // is no way to find the text cursor.
        let trusted = TextCaret.isTrusted(prompt: !askedForAccessibility)
        askedForAccessibility = true

        if trusted, let caret = TextCaret.rect() {
            menu.popUp(positioning: nil, at: NSPoint(x: caret.minX, y: caret.minY - 2), in: nil)
        } else {
            statusItem.button?.performClick(nil)
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if store.items.isEmpty {
            let empty = NSMenuItem(title: "Nothing copied yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        for (index, item) in store.items.enumerated() {
            let menuItem = NSMenuItem(title: "", action: #selector(pick(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = item.id
            switch item.kind {
            case .text:
                let text = item.text ?? ""
                menuItem.title = Preview.line(text, maxLength: settings.textLength)
                // Already sanitized and at most 1000 characters (HistoryStore.shortened).
                menuItem.toolTip = text
            case .image:
                menuItem.image = store.thumbnail(of: item, size: settings.imageSize)
                if let width = item.pixelWidth, let height = item.pixelHeight {
                    menuItem.toolTip = "Image, \(width) × \(height)"
                }
            }
            // Keys 1-9 pick the first nine entries while the menu is open.
            if index < 9 {
                menuItem.keyEquivalent = String(index + 1)
                menuItem.keyEquivalentModifierMask = []
            }
            menu.addItem(menuItem)
        }

        menu.addItem(.separator())
        let hint = NSMenuItem(title: "Hold ⇧ when picking to copy as plain text", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !store.items.isEmpty
        menu.addItem(clear)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let quit = NSMenuItem(title: "Quit CopyBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let item = store.item(id) else { return }
        let plainOnly = NSEvent.modifierFlags.contains(.shift)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .text where plainOnly:
            pasteboard.setString(store.fullText(of: item) ?? "", forType: .string)
        case .text:
            for (type, data) in store.representations(of: item) {
                pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
        case .image:
            for (type, data) in store.representations(of: item) {
                pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
                // Some apps only read TIFF.
                if type == NSPasteboard.PasteboardType.png.rawValue,
                   let tiff = NSBitmapImageRep(data: data)?.tiffRepresentation {
                    pasteboard.setData(tiff, forType: .tiff)
                }
            }
        }
        watcher.skipCurrentContents()
        store.moveToTop(id)
    }

    @objc private func clearHistory() {
        store.clear()
    }

    @objc private func openSettings() {
        config.createIfMissing()
        // `open -t` uses your default text editor; the file has no extension.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-t", config.url.path]
        do {
            try process.run()
        } catch {
            log.error("Could not open settings: \(error.localizedDescription, privacy: .public)")
        }
    }
}
