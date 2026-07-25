import Foundation
import AcaiQuality

/// A portable snapshot of the whole `ProjectStore`, for the manual "Export All Data" / "Import"
/// pair (`USABILITY_IMPROVEMENTS.md` Part 8, "Manual export/import of the whole project store" —
/// the bridge for "no iCloud sync"). Carries projects, diagram layouts, and quality-rule
/// configurations — deliberately **not** indexed `CodeArtifact` snapshots or cloned repository
/// contents: both are regenerable (reindex / re-fetch from remote) and can be large, so bundling
/// them would turn "export my setup" into "export my whole codebase cache," which isn't the point
/// (mirrors the doc's own call-out that cloned repository contents are excluded for the same
/// reason).
struct ProjectStoreExport: Codable {
    /// Bumped whenever this format's shape changes, so an older app version can tell "I don't
    /// understand this file" from "this file is corrupt" (`USABILITY_GUARDRAILS.md` §4) instead of
    /// silently misinterpreting a newer file.
    var formatVersion: Int
    var projects: [Project]
    var generatedDiagrams: [GeneratedDiagram]
    var freeformDiagrams: [FreeformDiagram]
    /// Managed (UI-authored) quality-rules files, keyed by codebase id. An *external* rules file
    /// the user pointed at isn't bundled here — it's just a path on this device, though
    /// `QualityCheckConfiguration.rulesPath` inside `projects` still records what it was; re-linking
    /// it on the receiving device is the same manual step as reconnecting any other external file
    /// reference.
    var managedQualityRules: [UUID: QualityRules]

    static let currentFormatVersion = 1

    init(
        projects: [Project],
        generatedDiagrams: [GeneratedDiagram],
        freeformDiagrams: [FreeformDiagram],
        managedQualityRules: [UUID: QualityRules]
    ) {
        self.formatVersion = Self.currentFormatVersion
        self.projects = projects
        self.generatedDiagrams = generatedDiagrams
        self.freeformDiagrams = freeformDiagrams
        self.managedQualityRules = managedQualityRules
    }
}

/// How `ProjectStore.importAllData(_:mode:)` reconciles an import against what's already local.
/// Deliberately coarse: this isn't sync, so there's no field-by-field conflict resolution — only
/// "keep what's already here" vs. "start over."
enum ProjectStoreImportMode: Equatable {
    /// Every project/diagram already on this device is deleted first, then everything from the
    /// import is added — the receiving device ends up an exact copy of the export.
    case replaceAll
    /// A project/diagram whose id isn't already present locally is added; one that already exists
    /// locally (same id) is left completely untouched, import or no.
    case merge
}
