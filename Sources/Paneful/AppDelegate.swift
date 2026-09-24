import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var trustTimer: Timer?
    private var wasTrusted: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        if !WindowAccess.isTrusted() { WindowAccess.requestTrust() }
        // Polling also catches permission being revoked while running.
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.updateTrust() }
        updateTrust()
    }

    private func updateTrust() {
        let trusted = WindowAccess.isTrusted()
        guard trusted != wasTrusted else { return }
        wasTrusted = trusted
        let symbol = trusted ? "rectangle.split.3x1" : "exclamationmark.triangle"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Paneful")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !WindowAccess.isTrusted() {
            menu.addItem(item("Grant Accessibility Access…", #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        }
        menu.addItem(item("Quit Paneful", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
