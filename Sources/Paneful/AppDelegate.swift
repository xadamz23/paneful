import AppKit
import PanefulCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let tiling = TilingController(store: SettingsStore(url: SettingsStore.defaultURL))
    private lazy var dragMonitor = DragMonitor(tiling: tiling, overlay: OverlayController())
    private lazy var hotKeys = HotKeys { [tiling = self.tiling] edge in tiling.moveFocusedWindow(toward: edge) }
    private lazy var editor = EditorWindowController(tiling: tiling)
    private var statusItem: NSStatusItem!
    private var trustTimer: Timer?
    private var wasTrusted: Bool?

    private static let gapChoices: [Double] = [0, 4, 8, 12, 16, 24, 32, 40]

    private struct LayoutChoice {
        let displayID: String
        let layout: Layout
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        WindowAccess.configureTimeout()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.tiling.refreshDisplays() }

        if !WindowAccess.isTrusted() { WindowAccess.requestTrust() }
        // Polling also catches permission being revoked while running.
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.updateTrust() }
        updateTrust()
    }

    private func updateTrust() {
        let trusted = WindowAccess.isTrusted()
        guard trusted != wasTrusted else { return }
        wasTrusted = trusted
        if trusted {
            dragMonitor.start()
            hotKeys.start()
        } else {
            dragMonitor.stop()
            hotKeys.stop()
        }
        let symbol = trusted ? "rectangle.split.3x1" : "exclamationmark.triangle"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Paneful")
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !WindowAccess.isTrusted() {
            menu.addItem(item("Grant Accessibility Access…", #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        }

        let header = NSMenuItem(title: "Layouts", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(item("Edit Layouts…", #selector(openEditor)))
        for display in tiling.displays {
            let current = tiling.settings.layout(forDisplay: display.id)
            let presets = Presets.available(for: display.visibleFrame, gap: tiling.gap)
            let submenu = NSMenu()
            if !presets.contains(current) {
                // An edited layout: shown ticked above the presets, which would replace it.
                let custom = NSMenuItem(title: current.name, action: nil, keyEquivalent: "")
                custom.state = .on
                submenu.addItem(custom)
                submenu.addItem(.separator())
            }
            for preset in presets {
                let choice = item(preset.name, #selector(chooseLayout(_:)))
                choice.representedObject = LayoutChoice(displayID: display.id, layout: preset)
                choice.state = preset == current ? .on : .off
                submenu.addItem(choice)
            }
            menu.addItem(parent(display.name, submenu))
        }
        menu.addItem(.separator())

        let gapMenu = NSMenu()
        for gap in Self.gapChoices {
            let choice = item("\(Int(gap)) px", #selector(chooseGap(_:)))
            choice.representedObject = gap
            choice.state = gap == tiling.settings.gap ? .on : .off
            gapMenu.addItem(choice)
        }
        menu.addItem(parent("Gap", gapMenu))

        menu.addItem(parent("Modifier", keyMenu(selected: tiling.settings.modifier, action: #selector(chooseModifier(_:)))))
        menu.addItem(parent("Span Key", keyMenu(selected: tiling.settings.spanModifier, action: #selector(chooseSpanModifier(_:)))))

        menu.addItem(item("Reset Arrangement", #selector(resetArrangement)))
        menu.addItem(.separator())

        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Quit Paneful", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func parent(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func keyMenu(selected: ModifierKey, action: Selector) -> NSMenu {
        let menu = NSMenu()
        for key in ModifierKey.allCases {
            let choice = item(key.title, action)
            choice.representedObject = key
            choice.state = key == selected ? .on : .off
            menu.addItem(choice)
        }
        return menu
    }

    @objc private func chooseLayout(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? LayoutChoice,
              let display = tiling.displays.first(where: { $0.id == choice.displayID }) else { return }
        tiling.setLayout(choice.layout, for: display)
    }

    @objc private func chooseGap(_ sender: NSMenuItem) {
        guard let gap = sender.representedObject as? Double else { return }
        tiling.setGap(gap)
    }

    @objc private func chooseModifier(_ sender: NSMenuItem) {
        guard let modifier = sender.representedObject as? ModifierKey else { return }
        tiling.setModifier(modifier)
    }

    @objc private func chooseSpanModifier(_ sender: NSMenuItem) {
        guard let modifier = sender.representedObject as? ModifierKey else { return }
        tiling.setSpanModifier(modifier)
    }

    @objc private func resetArrangement() {
        tiling.resetArrangements()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Paneful: launch at login failed: \(error)")
        }
    }

    @objc private func openEditor() {
        editor.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

extension ModifierKey {
    var title: String {
        switch self {
        case .shift: "Shift"
        case .option: "Option"
        case .control: "Control"
        case .command: "Command"
        }
    }
}
