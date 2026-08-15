import Foundation
import AcaiQuality

/// A named, reusable combination of a diagram `Selector` filter and (optionally) a codebase
/// `FileFilter`, saved once and applicable from any diagram's Filter section in the project.
struct FilterPreset: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var selector: AcaiQuality.Selector?
    var fileFilter: FileFilter?
}

/// The persisted, versioned container for a project's saved filter presets — mirrors
/// `FindingsSuppressionBaseline`'s shape (a `formatVersion` field, a plain array), so a project
/// with nothing saved yet and a future incompatible format both degrade to "no presets" rather
/// than a decode error.
struct FilterPresetList: Codable, Equatable, Sendable {
    var formatVersion = 1
    var presets: [FilterPreset] = []
}
