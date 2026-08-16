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
}
