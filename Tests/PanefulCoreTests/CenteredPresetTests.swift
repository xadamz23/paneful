import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct CenteredPresetTests {
    /// The Sceptre O35's usable area and a PA248QV, in Accessibility coordinates.
    let ultrawide = CGRect(x: 0, y: 31, width: 3440, height: 1327)
    let side = CGRect(x: -1920, y: 0, width: 1920, height: 1200)

    private func centered(in frame: CGRect, gap: CGFloat) throws -> Layout {
        try #require(Presets.available(for: frame, gap: gap).first { $0.name == Presets.centeredName })
    }

    @Test func middleIsExactly1440AndSidesFillTheRestAtTheCurrentGap() throws {
        let layout = try centered(in: ultrawide, gap: 4)
        #expect(layout.root.isValid)
        let rects = Geometry.zoneRects(layout.root, in: ultrawide, gap: 4)
        #expect(rects[0] == CGRect(x: 4, y: 35, width: 992, height: 1319))
        #expect(rects[1] == CGRect(x: 1000, y: 35, width: 1440, height: 1319))
        #expect(rects[2] == CGRect(x: 2444, y: 35, width: 992, height: 1319))
    }

    @Test func middleIsExactAtWhateverGapItIsPickedWith() throws {
        for gap: CGFloat in [0, 8, 16, 40] {
            let layout = try centered(in: ultrawide, gap: gap)
            #expect(Geometry.zoneRects(layout.root, in: ultrawide, gap: gap)[1]!.width == 1440, "gap \(gap)")
        }
    }

    @Test func offeredOnlyOnUltrawides() {
        #expect(Presets.available(for: side, gap: 4) == Presets.all)
        #expect(Presets.available(for: ultrawide, gap: 4).count == Presets.all.count + 1)
    }
}
