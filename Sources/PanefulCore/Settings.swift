import Foundation

public enum ModifierKey: String, Codable, CaseIterable, Sendable {
    case shift, option, control, command
}

public struct Settings: Codable, Equatable, Sendable {
    /// Space in points between zones and at screen edges, 0 to 40.
    public var gap: Double = 8
    public var modifier: ModifierKey = .shift
    /// Saved layout per display, keyed by display UUID.
    public var layouts: [String: Layout] = [:]

    public init() {}

    /// Missing or unreadable values fall back to their defaults, so an old or hand-edited file never blocks launch.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gap = min(max((try? container.decodeIfPresent(Double.self, forKey: .gap)) ?? 8, 0), 40)
        modifier = (try? container.decodeIfPresent(ModifierKey.self, forKey: .modifier)) ?? .shift
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
