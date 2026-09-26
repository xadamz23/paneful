import Foundation

public enum ModifierKey: String, Codable, CaseIterable, Sendable {
    case shift, option, control, command
}

public struct Settings: Codable, Equatable, Sendable {
    /// Space in points between zones and at screen edges, 0 to 40.
    public var gap: Double = 8
    /// Held while dragging a window to show zones. The three keys are never the same.
    public private(set) var modifier: ModifierKey = .shift
    /// Held as well as `modifier` to stretch the drop target across zones.
    public private(set) var spanModifier: ModifierKey = .option
    /// Held as well as `modifier` to split the zone under the cursor into top and bottom halves.
    public private(set) var splitModifier: ModifierKey = .control
    /// Saved layout per display, keyed by display UUID.
    public var layouts: [String: Layout] = [:]

    public init() {}

    /// Missing or unreadable values fall back to their defaults, so an old or hand-edited file never blocks launch.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gap = min(max((try? container.decodeIfPresent(Double.self, forKey: .gap)) ?? 8, 0), 40)
        modifier = (try? container.decodeIfPresent(ModifierKey.self, forKey: .modifier)) ?? .shift
        spanModifier = (try? container.decodeIfPresent(ModifierKey.self, forKey: .spanModifier)) ?? .option
        splitModifier = (try? container.decodeIfPresent(ModifierKey.self, forKey: .splitModifier)) ?? .control
        if spanModifier == modifier { spanModifier = ModifierKey.allCases.first { $0 != modifier }! }
        if splitModifier == modifier || splitModifier == spanModifier {
            splitModifier = ModifierKey.allCases.first { $0 != modifier && $0 != spanModifier }!
        }
        // Decode each display's layout on its own, so one bad entry doesn't discard the rest.
        if let entries = try? container.nestedContainer(keyedBy: DisplayKey.self, forKey: .layouts) {
            for key in entries.allKeys {
                if let layout = try? entries.decode(Layout.self, forKey: key) { layouts[key.stringValue] = layout }
            }
        }
    }

    /// The saved layout for a display, or Halves if none is saved or the saved one is invalid.
    public func layout(forDisplay id: String) -> Layout {
        // Flattened, because layouts saved before splits were flattened can have same-axis nesting.
        if let layout = layouts[id], layout.root.isValid { return Layout(name: layout.name, root: layout.root.flattened()) }
        return Presets.halves
    }

    /// Sets the snap modifier. Whichever other key had it takes the old modifier, so the keys never match.
    public mutating func setModifier(_ key: ModifierKey) { setKey(\.modifier, to: key) }

    /// Sets the span key. Whichever other key had it takes the old span key, so the keys never match.
    public mutating func setSpanModifier(_ key: ModifierKey) { setKey(\.spanModifier, to: key) }

    /// Sets the split key. Whichever other key had it takes the old split key, so the keys never match.
    public mutating func setSplitModifier(_ key: ModifierKey) { setKey(\.splitModifier, to: key) }

    private mutating func setKey(_ role: WritableKeyPath<Settings, ModifierKey>, to key: ModifierKey) {
        let old = self[keyPath: role]
        let keys: [WritableKeyPath<Settings, ModifierKey>] = [\.modifier, \.spanModifier, \.splitModifier]
        for other in keys where other != role && self[keyPath: other] == key {
            self[keyPath: other] = old
        }
        self[keyPath: role] = key
    }

    private struct DisplayKey: CodingKey {
        let stringValue: String
        init(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { return nil }
    }
}

public struct SettingsStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Paneful")
            .appendingPathComponent("settings.json")
    }

    /// Missing or corrupt files yield default settings.
    public func load() -> Settings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return settings
    }

    public func save(_ settings: Settings) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: url, options: .atomic)
    }
}
