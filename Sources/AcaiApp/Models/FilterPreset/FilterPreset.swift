import Foundation
import AcaiQuality

struct FilterPreset: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var selector: AcaiQuality.Selector?
    var fileFilter: FileFilter?
}

struct FilterPresetList: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion = Self.currentFormatVersion
    var presets: [FilterPreset] = []

    mutating func addPreset(name: String, selector: AcaiQuality.Selector?, fileFilter: FileFilter? = nil) {
        presets.append(FilterPreset(name: name, selector: selector, fileFilter: fileFilter))
    }

    /// No-op when `id` isn't in the list, so a rename that raced a delete never resurrects the preset.
    mutating func rename(_ id: UUID, to name: String) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].name = name
    }

    mutating func remove(_ id: UUID) {
        presets.removeAll { $0.id == id }
    }
}
