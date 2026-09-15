import Foundation
import Testing
import AcaiQuality
@testable import AcaiApp

/// `FilterPresetList`'s own add/rename/remove — the pure mutations `DiagramFilterSection` calls
/// before persisting via `FilterPresetStore`, kept separate so they're verifiable without SwiftUI.
@Suite("Filter Preset List")
struct FilterPresetListTests {
    @Test("Adding a preset appends it with the given name and selector")
    func addPresetAppends() {
        var list = FilterPresetList()
        list.addPreset(name: "Public repositories", selector: Selector(stereotype: "repository"))
        #expect(list.presets.map(\.name) == ["Public repositories"])
        #expect(list.presets.first?.selector == Selector(stereotype: "repository"))
    }

    @Test("Renaming an existing preset changes only its name")
    func renameChangesName() {
        var list = FilterPresetList()
        list.addPreset(name: "Original", selector: Selector(module: "UI"))
        let id = list.presets[0].id

        list.rename(id, to: "Renamed")

        #expect(list.presets.map(\.name) == ["Renamed"])
        #expect(list.presets.first?.selector == Selector(module: "UI"))
    }

    @Test("Renaming an id that isn't in the list changes nothing")
    func renameMissingIDIsNoOp() {
        var list = FilterPresetList()
        list.addPreset(name: "Kept", selector: nil)

        list.rename(UUID(), to: "Ignored")

        #expect(list.presets.map(\.name) == ["Kept"])
    }

    @Test("Removing a preset drops only that one")
    func removeDropsOnlyThatPreset() {
        var list = FilterPresetList()
        list.addPreset(name: "A", selector: nil)
        list.addPreset(name: "B", selector: nil)
        let idToRemove = list.presets[0].id

        list.remove(idToRemove)

        #expect(list.presets.map(\.name) == ["B"])
    }

    @Test("Removing an id that isn't in the list changes nothing")
    func removeMissingIDIsNoOp() {
        var list = FilterPresetList()
        list.addPreset(name: "Kept", selector: nil)

        list.remove(UUID())

        #expect(list.presets.map(\.name) == ["Kept"])
    }
}
