import Foundation
import Testing
import AcaiQuality
@testable import AcaiApp

/// `ProjectStore.exportAllData()`/`importAllData(_:mode:)` (B55): the manual "Export All Data" /
/// "Import" bridge for "no iCloud sync." Layer 0, per the backlog's own "export→import round-trip"
/// verification and `USABILITY_GUARDRAILS.md` §4's version-marker requirement.
@Suite("ProjectStore export/import")
@MainActor
struct ProjectStoreExportTests {

    private func withTempStoreDir<T>(_ body: (URL) throws -> T) rethrows -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-store-export-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    @Test("A fresh export carries the current format version")
    func exportCarriesCurrentFormatVersion() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            #expect(store.exportAllData().formatVersion == ProjectStoreExport.currentFormatVersion)
        }
    }

    @Test("Import round-trips projects, generated diagrams, and freeform diagrams")
    func importRoundTripsProjectsAndDiagrams() throws {
        try withTempStoreDir { sourceDir in
            try withTempStoreDir { targetDir in
                let codebaseID = UUID()
                var project = Project(title: "Demo", subtitle: "")
                let generated = GeneratedDiagram(
                    name: "Classes", content: .init(type: .classDiagram), codebaseID: codebaseID
                )
                let freeform = FreeformDiagram(name: "Sketch")
                project.generatedDiagramIDs = [generated.id]
                project.freeformDiagramIDs = [freeform.id]

                let source = ProjectStore(baseDir: sourceDir)
                source.projects.append(project)
                source.saveProject(project)
                source.saveGeneratedDiagram(generated)
                source.saveFreeformDiagram(freeform)
                let export = source.exportAllData()

                let target = ProjectStore(baseDir: targetDir)
                try target.importAllData(export, mode: .merge)

                #expect(target.projects.map(\.id) == [project.id])
                #expect(target.generatedDiagrams[generated.id]?.name == "Classes")
                #expect(target.freeformDiagrams[freeform.id]?.name == "Sketch")

                // Persisted to disk too, not just held in memory.
                let reloaded = ProjectStore(baseDir: targetDir)
                #expect(reloaded.projects.map(\.id) == [project.id])
            }
        }
    }

    @Test("Merge adds only what's missing locally, never overwriting an id that already exists")
    func mergeNeverOverwritesExistingIDs() throws {
        try withTempStoreDir { sourceDir in
            try withTempStoreDir { targetDir in
                let sharedID = UUID()
                let source = ProjectStore(baseDir: sourceDir)
                let sourceProject = Project(id: sharedID, title: "From Import", subtitle: "")
                source.projects.append(sourceProject)
                source.saveProject(sourceProject)
                let export = source.exportAllData()

                let target = ProjectStore(baseDir: targetDir)
                let localProject = Project(id: sharedID, title: "Local Edit", subtitle: "")
                let untouchedProject = Project(title: "Untouched", subtitle: "")
                target.projects = [localProject, untouchedProject]
                target.saveProject(localProject)
                target.saveProject(untouchedProject)

                try target.importAllData(export, mode: .merge)

                #expect(target.projects.count == 2)
                #expect(target.projects.first { $0.id == sharedID }?.title == "Local Edit")
                #expect(target.projects.contains { $0.title == "Untouched" })
            }
        }
    }

    @Test("Replace-all wipes everything local and leaves an exact copy of the import")
    func replaceAllWipesLocalDataFirst() throws {
        try withTempStoreDir { sourceDir in
            try withTempStoreDir { targetDir in
                let source = ProjectStore(baseDir: sourceDir)
                let sourceProject = Project(title: "From Import", subtitle: "")
                source.projects.append(sourceProject)
                source.saveProject(sourceProject)
                let export = source.exportAllData()

                let target = ProjectStore(baseDir: targetDir)
                let localOnlyProject = Project(title: "Local Only", subtitle: "")
                target.projects.append(localOnlyProject)
                target.saveProject(localOnlyProject)

                try target.importAllData(export, mode: .replaceAll)

                #expect(target.projects.map(\.id) == [sourceProject.id])
                let reloaded = ProjectStore(baseDir: targetDir)
                #expect(reloaded.projects.map(\.id) == [sourceProject.id])
            }
        }
    }

    @Test("Replace-all clears recently-viewed entries, since their local ids no longer exist")
    func replaceAllClearsRecentlyViewed() throws {
        try withTempStoreDir { sourceDir in
            try withTempStoreDir { targetDir in
                let source = ProjectStore(baseDir: sourceDir)
                let sourceProject = Project(title: "From Import", subtitle: "")
                source.projects.append(sourceProject)
                source.saveProject(sourceProject)
                let export = source.exportAllData()

                let target = ProjectStore(baseDir: targetDir)
                let localProject = Project(title: "Local Only", subtitle: "")
                target.projects.append(localProject)
                target.saveProject(localProject)
                target.recordOpened(.codebase(UUID()))

                try target.importAllData(export, mode: .replaceAll)

                #expect(target.recentlyViewed.recents.isEmpty)
                let reloaded = ProjectStore(baseDir: targetDir)
                #expect(reloaded.recentlyViewed.recents.isEmpty)
            }
        }
    }

    @Test("An imported indexed codebase lands as not-indexed, since its artifact was never bundled")
    func importedCodebaseLandsAsNotIndexed() throws {
        try withTempStoreDir { sourceDir in
            try withTempStoreDir { targetDir in
                let source = ProjectStore(baseDir: sourceDir)
                var codebase = Codebase(name: "Demo", directoryPath: "/tmp/demo")
                codebase.hasArtifact = true
                codebase.lastIndexed = Date()
                codebase.hasParseErrors = true
                codebase.parseDiagnosticCount = 3
                var project = Project(title: "Demo", subtitle: "")
                project.codebases = [codebase]
                source.projects.append(project)
                source.saveProject(project)
                let export = source.exportAllData()

                let target = ProjectStore(baseDir: targetDir)
                try target.importAllData(export, mode: .merge)

                let importedCodebase = try #require(target.projects.first?.codebases.first)
                #expect(!importedCodebase.hasArtifact)
                #expect(importedCodebase.lastIndexed == nil)
                #expect(!importedCodebase.hasParseErrors)
                #expect(importedCodebase.parseDiagnosticCount == 0)

                // The real failure mode: a fresh load must not choke trying to load an artifact
                // file that was never bundled and so was never written to `targetDir`.
                let reloaded = ProjectStore(baseDir: targetDir)
                #expect(reloaded.lastError == nil)
            }
        }
    }

    @Test("A newer-than-understood format version is rejected, not silently misread")
    func newerFormatVersionIsRejected() {
        withTempStoreDir { dir in
            var export = ProjectStore(baseDir: dir).exportAllData()
            export.formatVersion = ProjectStoreExport.currentFormatVersion + 1

            let store = ProjectStore(baseDir: dir)
            #expect(throws: ProjectStore.ImportError.self) {
                try store.importAllData(export, mode: .merge)
            }
        }
    }

    @Test("Managed quality rules round-trip through export/import")
    func managedQualityRulesRoundTrip() throws {
        try withTempStoreDir { sourceDir in
            try withTempStoreDir { targetDir in
                let codebaseID = UUID()
                let source = ProjectStore(baseDir: sourceDir)
                let rulesURL = try source.saveManagedRules(
                    QualityRules(includeGeneratedTypes: true), forCodebase: codebaseID
                )
                var codebase = Codebase(name: "Demo", directoryPath: "/tmp/demo")
                codebase.id = codebaseID
                codebase.qualityCheck = QualityCheckConfiguration(rulesPath: rulesURL.path)
                var project = Project(title: "Demo", subtitle: "")
                project.codebases = [codebase]
                source.projects.append(project)
                source.saveProject(project)

                let export = source.exportAllData()
                #expect(export.managedQualityRules[codebaseID]?.includeGeneratedTypes == true)

                let target = ProjectStore(baseDir: targetDir)
                try target.importAllData(export, mode: .merge)
                #expect(target.loadManagedRules(forCodebase: codebaseID)?.includeGeneratedTypes == true)
            }
        }
    }

    @Test("Merge never overwrites a local codebase's rules file when its project id already exists")
    func mergeNeverClobbersLocalRulesOnProjectCollision() throws {
        try withTempStoreDir { sourceDir in
            try withTempStoreDir { targetDir in
                let sharedProjectID = UUID()
                let codebaseID = UUID()

                let source = ProjectStore(baseDir: sourceDir)
                let importedRulesURL = try source.saveManagedRules(
                    QualityRules(includeGeneratedTypes: true), forCodebase: codebaseID
                )
                var sourceCodebase = Codebase(name: "Demo", directoryPath: "/tmp/demo")
                sourceCodebase.id = codebaseID
                sourceCodebase.qualityCheck = QualityCheckConfiguration(rulesPath: importedRulesURL.path)
                var sourceProject = Project(id: sharedProjectID, title: "Demo", subtitle: "")
                sourceProject.codebases = [sourceCodebase]
                source.projects.append(sourceProject)
                source.saveProject(sourceProject)
                let export = source.exportAllData()

                // The target already has a project with the *same id*, and its own codebase (same
                // codebase id, since a real collision reuses both) has different local rules.
                let target = ProjectStore(baseDir: targetDir)
                try target.saveManagedRules(QualityRules(includeGeneratedTypes: false), forCodebase: codebaseID)
                var localCodebase = Codebase(name: "Demo (local)", directoryPath: "/tmp/demo-local")
                localCodebase.id = codebaseID
                var localProject = Project(id: sharedProjectID, title: "Local Edit", subtitle: "")
                localProject.codebases = [localCodebase]
                target.projects = [localProject]
                target.saveProject(localProject)

                try target.importAllData(export, mode: .merge)

                #expect(target.projects.map(\.title) == ["Local Edit"])
                #expect(target.loadManagedRules(forCodebase: codebaseID)?.includeGeneratedTypes == false)
            }
        }
    }
}
