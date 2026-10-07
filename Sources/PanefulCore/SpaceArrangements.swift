/// Every display's arrangement on every Space, keyed by Space ID and display UUID, so each Space has its own
/// working dividers, split halves and tiled windows. An arrangement with no tiled windows isn't kept: it equals a
/// fresh one for its saved layout, because removing its last window resets it.
public struct SpaceArrangements<Window: Hashable> {
    public struct Key: Hashable, Sendable {
        public let space: Int
        public let display: String

        public init(space: Int, display: String) {
            self.space = space
            self.display = display
        }
    }

    private var stored: [Key: Arrangement<Window>] = [:]

    public init() {}

    /// The keys of arrangements with tiled windows.
    public var keys: [Key] { Array(stored.keys) }

    /// The arrangement under `key`, or a fresh one for `saved` if there's none.
    public func arrangement(_ key: Key, saved: Layout) -> Arrangement<Window> {
        stored[key] ?? Arrangement(saved: saved)
    }

    /// Keeps `arrangement` under `key`, or drops it if it has no tiled windows.
    public mutating func store(_ arrangement: Arrangement<Window>, at key: Key) {
        stored[key] = arrangement.tiledWindows.isEmpty ? nil : arrangement
    }

    /// Untiles `window` everywhere except under `key`, so it's tiled on one display of one Space at most.
    public mutating func untile(_ window: Window, except key: Key? = nil) {
        for other in stored.keys where other != key {
            guard var arrangement = stored[other] else { continue }
            arrangement.remove(window)
            store(arrangement, at: other)
        }
    }

    /// The display and zones `window` is tiled in on `space`.
    public func location(of window: Window, on space: Int) -> (display: String, zones: Set<ZoneID>)? {
        for (key, arrangement) in stored where key.space == space {
            if let zones = arrangement.zones(of: window) { return (key.display, zones) }
        }
        return nil
    }

    /// Whether `window` is tiled on any Space.
    public func isTiled(_ window: Window) -> Bool {
        stored.values.contains { $0.zones(of: window) != nil }
    }

    /// Rebases `display`'s arrangement on every Space on `saved` (see `Arrangement.rebased(on:)`).
    public mutating func rebase(display: String, on saved: Layout) {
        for key in stored.keys where key.display == display {
            guard let arrangement = stored[key] else { continue }
            store(arrangement.rebased(on: saved), at: key)
        }
    }

    /// Drops the arrangements of displays not in `displays`, on every Space.
    public mutating func keep(displays: Set<String>) {
        stored = stored.filter { displays.contains($0.key.display) }
    }
}
