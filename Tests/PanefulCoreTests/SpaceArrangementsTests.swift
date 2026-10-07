import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct SpaceArrangementsTests {
    typealias Key = SpaceArrangements<String>.Key
    let ultrawide = CGRect(x: 0, y: 31, width: 3440, height: 1327)
    /// The middle display on Space X, the same display on Space Y, and the left display on Space X.
    let x = Key(space: 8, display: "middle")
    let y = Key(space: 7, display: "middle")
    let side = Key(space: 8, display: "left")

    /// Tiles `window` in `zone` of Halves under `key`.
    func tile(_ window: String, in zone: ZoneID, at key: Key, _ arrangements: inout SpaceArrangements<String>) {
        var arrangement = arrangements.arrangement(key, saved: Presets.halves)
        arrangement.assign(window, to: zone)
        arrangements.store(arrangement, at: key)
    }

    @Test func missingKeyGivesAFreshArrangement() {
        let arrangements = SpaceArrangements<String>()
        let arrangement = arrangements.arrangement(x, saved: Presets.thirds)
        #expect(arrangement.working == Presets.thirds.root)
        #expect(arrangement.tiledWindows.isEmpty)
        #expect(arrangements.keys.isEmpty)
    }

    @Test func storedArrangementIsReadBack() {
        var arrangements = SpaceArrangements<String>()
        tile("a", in: 1, at: x, &arrangements)
        #expect(arrangements.arrangement(x, saved: Presets.halves).zones(of: "a") == [1])
        #expect(arrangements.keys == [x])
    }

    @Test func arrangementWithNoTiledWindowsIsDropped() {
        var arrangements = SpaceArrangements<String>()
        tile("a", in: 0, at: x, &arrangements)
        var arrangement = arrangements.arrangement(x, saved: Presets.halves)
        arrangement.remove("a")
        arrangements.store(arrangement, at: x)
        #expect(arrangements.keys.isEmpty)
    }

    @Test func movingADividerOnOneSpaceLeavesTheOtherSpaceAlone() {
        var arrangements = SpaceArrangements<String>()
        tile("onX", in: 0, at: x, &arrangements)
        tile("onY", in: 0, at: y, &arrangements)
        var onY = arrangements.arrangement(y, saved: Presets.halves)
        onY.moveEdge(.right, of: [0], to: 2000, in: ultrawide, gap: 8, minSize: 100)
        arrangements.store(onY, at: y)
        #expect(arrangements.arrangement(y, saved: Presets.halves).rects(in: ultrawide, gap: 8)[0]!.maxX == 2000)
        #expect(arrangements.arrangement(x, saved: Presets.halves).working == Presets.halves.root)
    }

    @Test func untileExceptKeyRemovesItFromOtherSpacesAndDisplays() {
        var arrangements = SpaceArrangements<String>()
        tile("a", in: 0, at: x, &arrangements)
        tile("b", in: 1, at: x, &arrangements)
        tile("a", in: 1, at: y, &arrangements)
        tile("a", in: 0, at: side, &arrangements)
        arrangements.untile("a", except: y)
        #expect(arrangements.arrangement(x, saved: Presets.halves).zones(of: "a") == nil)
        #expect(arrangements.arrangement(x, saved: Presets.halves).zones(of: "b") == [1])
        #expect(arrangements.arrangement(y, saved: Presets.halves).zones(of: "a") == [1])
        #expect(!arrangements.keys.contains(side))
    }

    @Test func untileWithNoKeyRemovesItEverywhere() {
        var arrangements = SpaceArrangements<String>()
        tile("a", in: 0, at: x, &arrangements)
        tile("a", in: 0, at: y, &arrangements)
        arrangements.untile("a")
        #expect(arrangements.keys.isEmpty)
    }

    @Test func locationIsFoundOnlyOnItsOwnSpace() {
        var arrangements = SpaceArrangements<String>()
        tile("a", in: 1, at: x, &arrangements)
        let found = arrangements.location(of: "a", on: 8)
        #expect(found?.display == "middle")
        #expect(found?.zones == [1])
        #expect(arrangements.location(of: "a", on: 7) == nil)
    }

    @Test func rebaseChangesTheDisplayOnEverySpace() {
        var arrangements = SpaceArrangements<String>()
        tile("a", in: 0, at: x, &arrangements)
        tile("b", in: 0, at: y, &arrangements)
        tile("c", in: 0, at: side, &arrangements)
        arrangements.rebase(display: "middle", on: Presets.thirds)
        #expect(arrangements.arrangement(x, saved: Presets.halves).saved == Presets.thirds)
        #expect(arrangements.arrangement(y, saved: Presets.halves).saved == Presets.thirds)
        #expect(arrangements.arrangement(x, saved: Presets.halves).zones(of: "a") == [0])
        #expect(arrangements.arrangement(side, saved: Presets.halves).saved == Presets.halves)
    }

    @Test func rebaseDropsArrangementsLeftEmpty() {
        var arrangements = SpaceArrangements<String>()
        var arrangement = arrangements.arrangement(x, saved: Presets.halves)
        arrangement.split(0, dropping: "a", intoTop: false, in: ultrawide, gap: 8, minSize: 100)
        arrangements.store(arrangement, at: x)
        arrangements.rebase(display: "middle", on: Presets.halves)
        #expect(arrangements.keys.isEmpty)
    }

    @Test func keepDropsDisconnectedDisplaysOnEverySpace() {
        var arrangements = SpaceArrangements<String>()
        tile("a", in: 0, at: x, &arrangements)
        tile("b", in: 0, at: y, &arrangements)
        tile("c", in: 0, at: side, &arrangements)
        arrangements.keep(displays: ["left"])
        #expect(arrangements.keys == [side])
    }
}
