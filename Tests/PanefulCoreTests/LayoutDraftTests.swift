import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct LayoutDraftTests {
    let ultrawide = CGRect(x: 0, y: 31, width: 3440, height: 1327)

    @Test func startsCleanWithNothingSelected() {
        let draft = LayoutDraft(original: Presets.halves)
        #expect(draft.layout == Presets.halves)
        #expect(!draft.isDirty)
        #expect(draft.selected == nil)
        #expect(!draft.canRemove)
    }

    @Test func applyingAPresetKeepsItsName() {
        var draft = LayoutDraft(original: Presets.halves)
        draft.selected = 1
        draft.apply(Presets.thirds)
        #expect(draft.layout == Presets.thirds)
        #expect(draft.isDirty)
        #expect(draft.selected == nil)
    }

    @Test func splitNamesTheLayoutCustom() {
        var draft = LayoutDraft(original: Presets.halves)
        draft.selected = 0
        draft.splitSelected(along: .vertical)
        #expect(draft.layout.name == LayoutDraft.customName)
        #expect(draft.layout.root.zoneIDs == [0, 2, 1])
        #expect(draft.selected == 0)
        #expect(draft.isDirty)
    }

    @Test func splitWithoutASelectionDoesNothing() {
        var draft = LayoutDraft(original: Presets.halves)
        draft.splitSelected(along: .vertical)
        #expect(!draft.isDirty)
    }

    @Test func removeClearsTheSelectionAndStopsAtOneZone() {
        var draft = LayoutDraft(original: Presets.halves)
        draft.selected = 1
        #expect(draft.canRemove)
        draft.removeSelected()
        #expect(draft.layout.root == .zone(0))
        #expect(draft.selected == nil)
        draft.selected = 0
        #expect(!draft.canRemove)
        draft.removeSelected()
        #expect(draft.layout.root == .zone(0))
    }

    @Test func movingADividerNamesTheLayoutCustom() {
        var draft = LayoutDraft(original: Presets.halves)
        draft.moveDivider(.right, of: 0, to: 2000, in: ultrawide, gap: 8, minSize: 100)
        #expect(draft.layout.name == LayoutDraft.customName)
        #expect(Geometry.zoneRects(draft.layout.root, in: ultrawide, gap: 8)[0]!.maxX == 2000)
    }

    @Test func revertRestoresTheOriginal() {
        var draft = LayoutDraft(original: Presets.grid2x2)
        draft.selected = 3
        draft.removeSelected()
        draft.revert()
        #expect(draft.layout == Presets.grid2x2)
        #expect(!draft.isDirty)
        #expect(draft.selected == nil)
    }
}
