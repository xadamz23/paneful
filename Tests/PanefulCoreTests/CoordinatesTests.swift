import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct CoordinatesTests {
    let primaryHeight: CGFloat = 1440

    @Test func flipPrimaryVisibleFrame() {
        let appKit = CGRect(x: 0, y: 82, width: 3440, height: 1327)
        #expect(Coordinates.flip(appKit, primaryScreenHeight: primaryHeight) == CGRect(x: 0, y: 31, width: 3440, height: 1327))
    }

    @Test func flipSecondaryDisplay() {
        let rightAppKit = CGRect(x: 3440, y: 240, width: 1920, height: 1200)
        let leftAppKit = CGRect(x: -1920, y: 240, width: 1920, height: 1200)
        #expect(Coordinates.flip(rightAppKit, primaryScreenHeight: primaryHeight) == CGRect(x: 3440, y: 0, width: 1920, height: 1200))
        #expect(Coordinates.flip(leftAppKit, primaryScreenHeight: primaryHeight) == CGRect(x: -1920, y: 0, width: 1920, height: 1200))
    }

    @Test func flipIsItsOwnInverse() {
        let rect = CGRect(x: -500, y: 123, width: 640, height: 480)
        #expect(Coordinates.flip(Coordinates.flip(rect, primaryScreenHeight: primaryHeight), primaryScreenHeight: primaryHeight) == rect)
    }

    @Test func flipPoint() {
        #expect(Coordinates.flip(CGPoint(x: 100, y: 1440), primaryScreenHeight: primaryHeight) == CGPoint(x: 100, y: 0))
        #expect(Coordinates.flip(CGPoint(x: -100, y: 0), primaryScreenHeight: primaryHeight) == CGPoint(x: -100, y: 1440))
    }
}
