import CoreGraphics

public enum Presets {
    public static let halves = Layout(
        name: "Halves",
        root: .split(.vertical, children: [.zone(0), .zone(1)], fractions: [0.5, 0.5]))

    public static let thirds = Layout(
        name: "Thirds",
        root: .split(.vertical, children: [.zone(0), .zone(1), .zone(2)], fractions: [1.0 / 3, 1.0 / 3, 1.0 / 3]))

    public static let sixtyForty = Layout(
        name: "60 / 40",
        root: .split(.vertical, children: [.zone(0), .zone(1)], fractions: [0.6, 0.4]))

    public static let fortySixty = Layout(
        name: "40 / 60",
        root: .split(.vertical, children: [.zone(0), .zone(1)], fractions: [0.4, 0.6]))

    public static let grid2x2 = Layout(
        name: "2 × 2",
        root: .split(.vertical, children: [
            .split(.horizontal, children: [.zone(0), .zone(1)], fractions: [0.5, 0.5]),
            .split(.horizontal, children: [.zone(2), .zone(3)], fractions: [0.5, 0.5]),
        ], fractions: [0.5, 0.5]))

    /// Large zone on the left, two stacked on the right.
    public static let onePlusTwo = Layout(
        name: "1 + 2",
        root: .split(.vertical, children: [
            .zone(0),
            .split(.horizontal, children: [.zone(1), .zone(2)], fractions: [0.5, 0.5]),
        ], fractions: [0.6, 0.4]))

    public static let all: [Layout] = [halves, thirds, sixtyForty, fortySixty, grid2x2, onePlusTwo]
}

extension Presets {
    public static let centeredName = "Thirds · 1440 middle"
    static let centeredWidth: CGFloat = 1440

    /// The presets offered for a display: the standard ones, plus on ultrawides (at least twice as wide as tall)
    /// thirds with a middle exactly `centeredWidth` wide at `gap`, the side zones sharing the rest.
    public static func available(for frame: CGRect, gap: CGFloat) -> [Layout] {
        let content = frame.width - 4 * gap   // two screen-edge gaps and two gaps between zones
        guard frame.width >= 2 * frame.height, content > centeredWidth else { return all }
        let middle = Double(centeredWidth / content)
        let side = (1 - middle) / 2
        let centered = Layout(
            name: centeredName,
            root: .split(.vertical, children: [.zone(0), .zone(1), .zone(2)], fractions: [side, middle, side]))
        return all + [centered]
    }
}
