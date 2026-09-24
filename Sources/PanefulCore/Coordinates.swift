import CoreGraphics

/// Converts between AppKit global coordinates (bottom-left origin, y up) and Accessibility
/// global coordinates (top-left origin of the primary display, y down). Each flip is its own inverse.
public enum Coordinates {
    public static func flip(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func flip(_ point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }
}
