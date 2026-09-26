import Foundation
import Testing
@testable import PanefulCore

@Suite struct SettingsTests {
    private func tempStore() -> SettingsStore {
        SettingsStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("settings.json"))
    }

    private func store(containing json: String) throws -> SettingsStore {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: store.url)
        return store
    }

    @Test func defaults() {
        let settings = Settings()
        #expect(settings.gap == 8)
        #expect(settings.modifier == .shift)
        #expect(settings.spanModifier == .option)
        #expect(settings.splitModifier == .control)
        #expect(settings.layouts.isEmpty)
    }

    @Test func missingFileGivesDefaults() {
        #expect(tempStore().load() == Settings())
    }

    @Test func corruptFileGivesDefaults() throws {
        #expect(try store(containing: "not json").load() == Settings())
        #expect(try store(containing: "[1, 2]").load() == Settings())
    }

    @Test func partialFileKeepsKnownValues() throws {
        let settings = try store(containing: #"{"gap": 12}"#).load()
        #expect(settings.gap == 12)
        #expect(settings.modifier == .shift)
        #expect(settings.spanModifier == .option)
        #expect(settings.splitModifier == .control)
        #expect(settings.layouts.isEmpty)
    }

    @Test func unknownModifierFallsBackToShift() throws {
        let settings = try store(containing: #"{"gap": 4, "modifier": "hyper"}"#).load()
        #expect(settings.gap == 4)
        #expect(settings.modifier == .shift)
    }

    @Test func unknownSpanKeyFallsBackToOption() throws {
        #expect(try store(containing: #"{"spanModifier": "hyper"}"#).load().spanModifier == .option)
    }

    @Test func equalKeysOnLoadFallBack() throws {
        // An older file that set the snap modifier to Option, before the span key existed.
        let settings = try store(containing: #"{"modifier": "option"}"#).load()
        #expect(settings.modifier == .option)
        #expect(settings.spanModifier == .shift)
    }

    @Test func settingTheModifierToTheSpanKeySwapsThem() {
        var settings = Settings()
        settings.setModifier(.option)
        #expect(settings.modifier == .option)
        #expect(settings.spanModifier == .shift)
    }

    @Test func settingTheSpanKeyToTheModifierSwapsThem() {
        var settings = Settings()
        settings.setSpanModifier(.shift)
        #expect(settings.spanModifier == .shift)
        #expect(settings.modifier == .option)
    }

    @Test func settingAnUnusedKeyDoesNotSwap() {
        var settings = Settings()
        settings.setSpanModifier(.command)
        #expect(settings.spanModifier == .command)
        #expect(settings.modifier == .shift)
        #expect(settings.splitModifier == .control)
    }

    @Test func unknownSplitKeyFallsBackToControl() throws {
        #expect(try store(containing: #"{"splitModifier": "hyper"}"#).load().splitModifier == .control)
    }

    @Test func splitKeyEqualToAnotherKeyOnLoadFallsBack() throws {
        let fromModifier = try store(containing: #"{"modifier": "control"}"#).load()
        #expect(fromModifier.modifier == .control)
        #expect(fromModifier.spanModifier == .option)
        #expect(fromModifier.splitModifier == .shift)
        let fromSpan = try store(containing: #"{"spanModifier": "control"}"#).load()
        #expect(fromSpan.spanModifier == .control)
        #expect(fromSpan.splitModifier == .option)
    }

    @Test func settingTheSplitKeyToTheModifierSwapsThem() {
        var settings = Settings()
        settings.setSplitModifier(.shift)
        #expect(settings.splitModifier == .shift)
        #expect(settings.modifier == .control)
        #expect(settings.spanModifier == .option)
    }

    @Test func settingTheSpanKeyToTheSplitKeySwapsThem() {
        var settings = Settings()
        settings.setSpanModifier(.control)
        #expect(settings.spanModifier == .control)
        #expect(settings.splitModifier == .option)
        #expect(settings.modifier == .shift)
    }

    @Test func settingTheModifierToTheSplitKeySwapsThem() {
        var settings = Settings()
        settings.setModifier(.control)
        #expect(settings.modifier == .control)
        #expect(settings.splitModifier == .shift)
    }

    @Test func gapIsClamped() throws {
        #expect(try store(containing: #"{"gap": 100}"#).load().gap == 40)
        #expect(try store(containing: #"{"gap": -5}"#).load().gap == 0)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let store = tempStore()
        var settings = Settings()
        settings.gap = 16
        settings.setModifier(.command)
        settings.setSpanModifier(.control)
        settings.layouts["B04199E5-A47E-4E90-8D02-B248A7B36CBE"] = Presets.thirds
        try store.save(settings)
        #expect(store.load() == settings)
    }

    @Test func unknownDisplayGetsHalves() {
        #expect(Settings().layout(forDisplay: "nope") == Presets.halves)
    }

    @Test func savedLayoutIsReturned() {
        var settings = Settings()
        settings.layouts["A"] = Presets.grid2x2
        #expect(settings.layout(forDisplay: "A") == Presets.grid2x2)
    }

    @Test func invalidSavedLayoutFallsBackToHalves() {
        var settings = Settings()
        settings.layouts["A"] = Layout(name: "Bad", root: .split(.vertical, children: [.zone(0), .zone(1)], fractions: [0.5, 0.2]))
        #expect(settings.layout(forDisplay: "A") == Presets.halves)
    }

    @Test func oneBadLayoutKeepsTheOthers() throws {
        let thirds = String(decoding: try JSONEncoder().encode(Presets.thirds), as: UTF8.self)
        let settings = try store(containing: #"{"layouts": {"A": \#(thirds), "B": {"name": "x"}}}"#).load()
        #expect(settings.layout(forDisplay: "A") == Presets.thirds)
        #expect(settings.layouts["B"] == nil)
    }

    @Test func savedSameAxisNestingIsFlattenedOnLoad() {
        // Layouts saved before splits were flattened can nest a side-by-side split inside another,
        // which makes dragging the outer divider move the inner one too.
        var settings = Settings()
        settings.layouts["A"] = Layout(name: "Custom", root: .split(.vertical, children: [
            .zone(0),
            .split(.vertical, children: [.zone(3), .zone(2)], fractions: [0.5, 0.5]),
        ], fractions: [0.4, 0.6]))
        #expect(settings.layout(forDisplay: "A").root == .split(.vertical, children: [.zone(0), .zone(3), .zone(2)], fractions: [0.4, 0.3, 0.3]))
    }
}
