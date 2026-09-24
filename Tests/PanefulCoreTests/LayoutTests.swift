import Foundation
import Testing
@testable import PanefulCore

@Suite struct LayoutTests {
    @Test(arguments: Presets.all)
    func presetsAreValid(_ layout: Layout) {
        #expect(layout.root.isValid, "\(layout.name)")
    }

    @Test func presetNamesAreUnique() {
        #expect(Set(Presets.all.map(\.name)).count == Presets.all.count)
    }

    @Test func zoneIDsAreDepthFirst() {
        #expect(Presets.grid2x2.root.zoneIDs == [0, 1, 2, 3])
        #expect(Presets.onePlusTwo.root.zoneIDs == [0, 1, 2])
    }

    @Test func rejectsMalformedSplits() {
        let z0 = Node.zone(0), z1 = Node.zone(1)
        #expect(!Node.split(.vertical, children: [z0, z1], fractions: [0.5, 0.2]).isValid)   // doesn't sum to 1
        #expect(!Node.split(.vertical, children: [z0, z1], fractions: [1.0]).isValid)        // count mismatch
        #expect(!Node.split(.vertical, children: [z0, z1], fractions: [1.0, 0]).isValid)     // zero-size child
        #expect(!Node.split(.vertical, children: [z0], fractions: [1.0]).isValid)            // single child
        #expect(!Node.split(.vertical, children: [z0, z0], fractions: [0.5, 0.5]).isValid)   // duplicate zone ID
        let nestedBad = Node.split(.vertical, children: [z0, .split(.horizontal, children: [z1, .zone(2)], fractions: [0.9, 0.9])], fractions: [0.5, 0.5])
        #expect(!nestedBad.isValid)
    }

    @Test func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(Presets.onePlusTwo)
        #expect(try JSONDecoder().decode(Layout.self, from: data) == Presets.onePlusTwo)
    }
}
