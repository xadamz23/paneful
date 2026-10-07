import CoreGraphics

// Private SkyLight functions, re-exported by CoreGraphics. They're read-only and work with SIP on.
@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSGetActiveSpace") private func CGSGetActiveSpace(_ connection: Int32) -> Int

/// The only place Paneful calls the private Space functions.
enum Spaces {
    /// The current Space's ID, or 0 if the window server doesn't give one, which puts everything on one shared Space.
    /// With "Displays have separate Spaces" off, every display is on this Space. It's read fresh on each call, so
    /// Paneful needs no Space-change notification.
    static func current() -> Int {
        CGSGetActiveSpace(CGSMainConnectionID())
    }
}
