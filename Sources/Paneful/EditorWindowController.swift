import AppKit
import SwiftUI

/// The Edit Layouts window.
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private let model: EditorModel

    init(tiling: TilingController) {
        model = EditorModel(tiling: tiling)
        let window = EditorWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 580),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Paneful Layouts"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: EditorView(model: model))
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("EditorWindowController is not loaded from a nib")
    }

    func show() {
        if window?.isVisible != true { model.reload() }
        // Paneful is a menu bar app, so it has to bring itself forward.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model.reloadIfUnchanged()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.confirmDiscardingChanges()
    }

    /// Whether Paneful may quit: the editor is closed, or its edits were saved or discarded. A closed editor can
    /// still hold edits discarded on close, which `show()` drops.
    func confirmQuit() -> Bool {
        window?.isVisible != true || model.confirmDiscardingChanges()
    }
}

/// Closes on Esc and Cmd-W. A menu bar app has no main menu to provide them.
private final class EditorWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
