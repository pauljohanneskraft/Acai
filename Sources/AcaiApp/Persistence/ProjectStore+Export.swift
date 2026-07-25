import Foundation
import AcaiQuality

extension ProjectStore {
    /// Packages every project, diagram layout, and managed quality-rule configuration currently
    /// held into one versioned `ProjectStoreExport`. See its doc comment for what's deliberately
    /// excluded (indexed artifacts, cloned repository contents).
    func exportAllData() -> ProjectStoreExport {
        var managedRules: [UUID: QualityRules] = [:]
        for project in projects {
            for codebase in project.codebases {
                guard let path = codebase.qualityCheck?.rulesPath, isManaged(path: path),
                      let loaded = loadManagedRules(forCodebase: codebase.id) else { continue }
                managedRules[codebase.id] = loaded
            }
        }
        return ProjectStoreExport(
            projects: projects,
            generatedDiagrams: Array(generatedDiagrams.values),
            freeformDiagrams: Array(freeformDiagrams.values),
            managedQualityRules: managedRules
        )
    }

    /// An import-specific failure, distinct from the ordinary I/O failures `report(_:)` already
    /// handles per-file.
    enum ImportError: LocalizedError {
        case unsupportedFormatVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedFormatVersion(let version):
                return "This export (format \(version)) is newer than this version of Acai " +
                    "understands. Update the app and try again."
            }
        }
    }

    /// Imports `export` per `mode` (see `ProjectStoreImportMode`). Every project/diagram/rules file
    /// actually added is persisted to disk immediately, the same way any other mutation is —
    /// nothing about import is held only in memory.
    func importAllData(_ export: ProjectStoreExport, mode: ProjectStoreImportMode) throws {
        guard export.formatVersion <= ProjectStoreExport.currentFormatVersion else {
            throw ImportError.unsupportedFormatVersion(export.formatVersion)
        }

        if mode == .replaceAll {
            for project in projects { deleteProjectFile(project.id) }
            for id in generatedDiagrams.keys { deleteGeneratedDiagramFile(id) }
            for id in freeformDiagrams.keys { deleteFreeformDiagramFile(id) }
            projects = []
            generatedDiagrams = [:]
            freeformDiagrams = [:]
            recentlyViewed = RecentlyViewed()
            saveRecentlyViewed()
        }

        // Codebases carry indexing state (`hasArtifact`/`lastIndexed`/parse-diagnostic counts)
        // pointing at an artifact file that `exportAllData()` deliberately never bundled. Importing
        // that state verbatim would leave `hasArtifact == true` with no `codebase_<id>.json` on
        // disk — `load()`'s next `loadArtifact` call hits a missing file, which isn't a
        // `DecodingError`, so it skips the "mark not indexed" recovery and instead surfaces a
        // spurious error alert. Landing every imported codebase as "not indexed" (reindex re-derives
        // it) is the only state that's actually true on the receiving device.
        var addedCodebaseIDs: Set<UUID> = []
        let existingProjectIDs = Set(projects.map(\.id))
        for var project in export.projects where mode == .replaceAll || !existingProjectIDs.contains(project.id) {
            for index in project.codebases.indices {
                project.codebases[index].hasArtifact = false
                project.codebases[index].lastIndexed = nil
                project.codebases[index].hasParseErrors = false
                project.codebases[index].parseDiagnosticCount = 0
                addedCodebaseIDs.insert(project.codebases[index].id)
            }
            projects.append(project)
            saveProject(project)
        }
        let existingGeneratedIDs = Set(generatedDiagrams.keys)
        for diagram in export.generatedDiagrams
        where mode == .replaceAll || !existingGeneratedIDs.contains(diagram.id) {
            saveGeneratedDiagram(diagram)
        }
        let existingFreeformIDs = Set(freeformDiagrams.keys)
        for diagram in export.freeformDiagrams
        where mode == .replaceAll || !existingFreeformIDs.contains(diagram.id) {
            saveFreeformDiagram(diagram)
        }
        // Only for codebases that actually landed above — a codebase whose project collided with an
        // existing id (and was therefore skipped, "local wins") must keep its own local rules file
        // untouched, not have it clobbered by the import's copy.
        for (codebaseID, rules) in export.managedQualityRules where addedCodebaseIDs.contains(codebaseID) {
            _ = try? saveManagedRules(rules, forCodebase: codebaseID)
        }
    }
}
