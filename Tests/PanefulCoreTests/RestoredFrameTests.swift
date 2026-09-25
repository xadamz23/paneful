import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct RestoredFrameTests {
    /// Usable areas in Accessibility coordinates: the ultrawide and the left PA248QV.
    let ultrawide = CGRect(x: 0, y: 31, width: 3440, height: 1327)
    let left = CGRect(x: -1920, y: 0, width: 1920, height: 1200)

    @Test func keepsTheGrabPointUnderTheCursorAndTheTopEdge() {
        // Grabbed in the middle of the title bar: the restored window stays centred on the cursor.
        let current = CGRect(x: 100, y: 100, width: 1700, height: 1200)
        let restored = Geometry.restoredFrame(from: current, to: CGSize(width: 800, height: 600), grab: CGPoint(x: 950, y: 110), within: ultrawide)
        #expect(restored == CGRect(x: 550, y: 100, width: 800, height: 600))
    }

    @Test func grabAtTheLeftEdgeKeepsTheLeftEdge() {
        let current = CGRect(x: 100, y: 100, width: 1700, height: 1200)
        let restored = Geometry.restoredFrame(from: current, to: CGSize(width: 800, height: 600), grab: CGPoint(x: 100, y: 110), within: ultrawide)
        #expect(restored == CGRect(x: 100, y: 100, width: 800, height: 600))
    }

    @Test func staysOnTheDisplay() {
        // Dropped near the bottom-right corner with a bigger saved size: pushed back inside.
        let current = CGRect(x: 2600, y: 900, width: 800, height: 400)
        let restored = Geometry.restoredFrame(from: current, to: CGSize(width: 1600, height: 1000), grab: CGPoint(x: 3000, y: 910), within: ultrawide)
        #expect(restored == CGRect(x: 1840, y: 358, width: 1600, height: 1000))
    }

    @Test func neverLargerThanTheDisplay() {
        let current = CGRect(x: 100, y: 100, width: 800, height: 600)
        let restored = Geometry.restoredFrame(from: current, to: CGSize(width: 5000, height: 2000), grab: CGPoint(x: 500, y: 110), within: ultrawide)
        #expect(restored == ultrawide)
    }

    @Test func worksOnADisplayLeftOfThePrimary() {
        let current = CGRect(x: -900, y: 600, width: 900, height: 600)
        let restored = Geometry.restoredFrame(from: current, to: CGSize(width: 1200, height: 800), grab: CGPoint(x: -450, y: 610), within: left)
        #expect(restored == CGRect(x: -1200, y: 400, width: 1200, height: 800))
    }

    @Test func landsOnWholePoints() {
        let current = CGRect(x: 100, y: 100, width: 1700, height: 1200)
        let restored = Geometry.restoredFrame(from: current, to: CGSize(width: 800, height: 600), grab: CGPoint(x: 110, y: 110), within: ultrawide)
        #expect(restored.minX == restored.minX.rounded())
        #expect(restored.minY == restored.minY.rounded())
    }
}
