import AppKit
import PanefulCore

/// Owns settings and each display's arrangement, and moves windows into zones.
final class TilingController {
    private let store: SettingsStore
    private(set) var settings: Settings
    private(set) var displays: [Display] = []
    private var arrangements: [String: Arrangement<AXUIElement>] = [:]

    init(store: SettingsStore) {
        self.store = store
        settings = store.load()
        refreshDisplays()
    }

    var gap: CGFloat { CGFloat(settings.gap) }

    /// Re-reads connected displays. Arrangements restart from saved layouts, keeping tiled windows, which are re-fitted.
    func refreshDisplays() {
        displays = Displays.current()
        let old = arrangements
        arrangements = [:]
        for display in displays {
            let layout = settings.layout(forDisplay: display.id)
            arrangements[display.id] = old[display.id]?.rebased(on: layout) ?? Arrangement(saved: layout)
            refit(display)
        }
    }

    func display(containing point: CGPoint) -> Display? {
        displays.first { $0.frame.contains(point) }
    }

    func zoneRects(for display: Display) -> [ZoneID: CGRect] {
        arrangements[display.id]?.rects(in: display.visibleFrame, gap: gap) ?? [:]
    }

    func snap(_ window: AXUIElement, to zone: ZoneID, on display: Display) {
        guard let rect = zoneRects(for: display)[zone] else { return }
        untile(window)
        arrangements[display.id]?.assign(window, to: zone)
        WindowAccess.setFrame(rect, of: window)
    }

    func untile(_ window: AXUIElement) {
        for id in arrangements.keys { arrangements[id]?.remove(window) }
    }

    func resetArrangements() {
        for display in displays {
            arrangements[display.id]?.reset()
            refit(display)
        }
    }

    func setLayout(_ layout: Layout, for display: Display) {
        settings.layouts[display.id] = layout
        save()
        arrangements[display.id] = arrangements[display.id]?.rebased(on: layout) ?? Arrangement(saved: layout)
        refit(display)
    }

    func setGap(_ gap: Double) {
        settings.gap = gap
        save()
        displays.forEach(refit)
    }

    func setModifier(_ modifier: ModifierKey) {
        settings.modifier = modifier
        save()
    }

    private func refit(_ display: Display) {
        guard let arrangement = arrangements[display.id] else { return }
        let rects = arrangement.rects(in: display.visibleFrame, gap: gap)
        for window in arrangement.tiledWindows {
            guard let zone = arrangement.zone(of: window), let rect = rects[zone] else { continue }
            if !WindowAccess.setFrame(rect, of: window) { arrangements[display.id]?.remove(window) }
        }
    }

    private func save() {
        do { try store.save(settings) } catch { NSLog("Paneful: failed to save settings: \(error)") }
    }
}
