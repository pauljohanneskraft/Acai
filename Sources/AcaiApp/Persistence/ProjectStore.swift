import Foundation
import AcaiQuality
import AcaiCore
import Yams

/// Per-file persistence layout:
/// ```
/// <baseDir>/
///   projects/
///     <projectID>.json     – Project struct (includes codebases, diagram IDs)
///   diagrams/
///     generated_<diagramID>.json  – GeneratedDiagram
///     freeform_<diagramID>.json     – FreeformDiagram
///   artifacts/
///     codebase_<codebaseID>.json – CodeArtifact (analysis result)
/// ```
final class ProjectStore: ObservableObject {
    @Published var projects: [Project] = []

    /// In-memory cache of loaded diagrams, keyed by ID.
    @Published var generatedDiagrams: [UUID: GeneratedDiagram] = [:]
    @Published var freeformDiagrams: [UUID: FreeformDiagram] = [:]

    /// In-memory cache of loaded artifacts, keyed by codebase ID.
    @Published var artifacts: [UUID: CodeArtifact] = [:]

    /// The most recent load/save failure, surfaced to the UI (e.g. via an alert). Replaces the
    /// old `print`-and-swallow so a failed write doesn't silently look successful.
    @Published var lastError: StoreError?

    /// A user-presentable persistence error. `Identifiable` so SwiftUI `.alert(item:)` can bind it.
    struct StoreError: Identifiable {
        let id = UUID()
        let message: String
    }

    /// Records a failure both to the console (for logs) and to `lastError` (for the UI).
    func report(_ message: String) {
        print(message)
        lastError = StoreError(message: message)
    }

    let baseDir: URL
    private var projectsDir: URL { baseDir.appendingPathComponent("projects", isDirectory: true) }
    private var diagramsDir: URL { baseDir.appendingPathComponent("diagrams", isDirectory: true) }
    private var artifactsDir: URL { baseDir.appendingPathComponent("artifacts", isDirectory: true) }
    /// Holds YAML rules files for UI-authored code-quality checks (one per codebase). A check whose
    /// `rulesPath` resolves inside this directory is "managed" — editable in the form; any other
    /// path is an external file the user referenced.
    private var rulesDir: URL { baseDir.appendingPathComponent("rules", isDirectory: true) }
    /// Holds the app-managed local folders for GitHub-backed codebases (see `GitHubSource`), one
    /// subdirectory per codebase, named by its id — parallels `artifactsDir`/`rulesDir`.
    var githubClonesDir: URL { baseDir.appendingPathComponent("github-clones", isDirectory: true) }

    init(baseDir: URL? = nil) {
        let fileManager = FileManager.default
        if let baseDir {
            self.baseDir = baseDir
        } else {
            #if os(macOS)
            let appSupport = try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let bundleID = Bundle.main.bundleIdentifier ?? "AcaiApp"
            self.baseDir = (appSupport ?? fileManager.homeDirectoryForCurrentUser)
                .appendingPathComponent(bundleID, isDirectory: true)
            #else
            self.baseDir = (fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory)
                .appendingPathComponent("AcaiApp", isDirectory: true)
            #endif
        }
        try? fileManager.createDirectory(at: self.baseDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: diagramsDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: artifactsDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: rulesDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: githubClonesDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Load

    func load() {
        let fileManager = FileManager.default
        let decoder = JSONDecoder()

        do {
            let projectURLs = try fileManager.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)
            for projectURL in projectURLs where projectURL.pathExtension == "json" {
                do {
                    let pData = try Data(contentsOf: projectURL)
                    let project = try decoder.decode(Project.self, from: pData)
                    projects.append(project)
                    for diagramID in project.generatedDiagramIDs {
                        loadGeneratedDiagram(diagramID)
                    }
                    for diagramID in project.freeformDiagramIDs {
                        loadFreeformDiagram(diagramID)
                    }
                    for codebase in project.codebases where codebase.hasArtifact {
                        loadArtifact(for: codebase.id)
                    }
                } catch {
                    report("Failed to load project at \(projectURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
        } catch {
            report("Failed to load project directory: \(error.localizedDescription)")
        }
    }

    func loadGeneratedDiagram(_ id: UUID) {
        guard generatedDiagrams[id] == nil else { return }
        let url = diagramsDir.appendingPathComponent("generated_\(id.uuidString).json")
        do {
            let data = try Data(contentsOf: url)
            generatedDiagrams[id] = try JSONDecoder().decode(GeneratedDiagram.self, from: data)
        } catch {
            report("Failed to load a generated diagram: \(error.localizedDescription)")
        }
    }

    func loadFreeformDiagram(_ id: UUID) {
        guard freeformDiagrams[id] == nil else { return }
        let url = diagramsDir.appendingPathComponent("freeform_\(id.uuidString).json")
        do {
            let data = try Data(contentsOf: url)
            freeformDiagrams[id] = try JSONDecoder().decode(FreeformDiagram.self, from: data)
        } catch {
            report("Failed to load a freeform diagram: \(error.localizedDescription)")
        }
    }

    /// Versioned envelope around a persisted `CodeArtifact`. Bumping ``currentArtifactFormat`` makes
    /// `loadArtifact` treat older stored analyses as stale so the UI offers Reindex — this is how a
    /// change in *what* the artifact stores is migrated. v2 persists the **semantic** (un-flattened)
    /// artifact so nesting-depth and other tree-shaped metrics are computed correctly; v1 (the
    /// pre-envelope bare `CodeArtifact`) stored the display-flattened form and read nesting as 0.
    private struct StoredArtifact: Codable {
        var formatVersion: Int
        var artifact: CodeArtifact
    }

    /// Current on-disk artifact format. A file with a lower version — or a pre-envelope bare
    /// `CodeArtifact` (which fails to decode as ``StoredArtifact``) — is dropped back to "not indexed".
    private static let currentArtifactFormat = 2

    func loadArtifact(for codebaseID: UUID) {
        guard artifacts[codebaseID] == nil else { return }
        let url = artifactsDir.appendingPathComponent("codebase_\(codebaseID.uuidString).json")
        do {
            let data = try Data(contentsOf: url)
            let stored = try JSONDecoder().decode(StoredArtifact.self, from: data)
            guard stored.formatVersion >= Self.currentArtifactFormat else {
                // An older format (e.g. the pre-fix display-flattened artifact) — reindex to regenerate.
                markCodebaseNotIndexed(codebaseID)
                return
            }
            artifacts[codebaseID] = stored.artifact
        } catch is DecodingError {
            // Predates the versioned envelope (bare `CodeArtifact`) or a schema change (e.g. the
            // now-required `accessLevel`). Treat the codebase as never indexed so the UI offers
            // Reindex, rather than surfacing a decode error the user can't act on.
            markCodebaseNotIndexed(codebaseID)
        } catch {
            report("Failed to load a stored analysis: \(error.localizedDescription)")
        }
    }

    /// Marks a codebase as un-indexed and persists it, so a stored analysis that can no longer be
    /// decoded drops back to the "not indexed" state (dashed status + Reindex action).
    private func markCodebaseNotIndexed(_ codebaseID: UUID) {
        for projectIndex in projects.indices {
            guard let codebaseIndex = projects[projectIndex].codebases
                .firstIndex(where: { $0.id == codebaseID }) else { continue }
            projects[projectIndex].codebases[codebaseIndex].hasArtifact = false
            saveProject(projects[projectIndex])
            return
        }
    }

    // MARK: - Artifact Access

    func artifact(for codebaseID: UUID) -> CodeArtifact? {
        artifacts[codebaseID]
    }

    // MARK: - Save

    func save() {
        for project in projects {
            saveProject(project)
        }
        for diagram in generatedDiagrams.values {
            saveGeneratedDiagram(diagram)
        }
        for diagram in freeformDiagrams.values {
            saveFreeformDiagram(diagram)
        }
        for (codebaseID, artifact) in artifacts {
            saveArtifact(artifact, for: codebaseID)
        }
    }

    func saveProject(_ project: Project) {
        let encoder = JSONEncoder()
        let url = projectsDir.appendingPathComponent("\(project.id.uuidString).json")
        do {
            try encoder.encode(project).write(to: url, options: .atomic)
        } catch {
            report("Failed to save project “\(project.title)”: \(error.localizedDescription)")
        }
    }

    func saveGeneratedDiagram(_ diagram: GeneratedDiagram) {
        generatedDiagrams[diagram.id] = diagram
        let encoder = JSONEncoder()
        let url = diagramsDir.appendingPathComponent("generated_\(diagram.id.uuidString).json")
        do {
            try encoder.encode(diagram).write(to: url, options: .atomic)
        } catch {
            report("Failed to save diagram “\(diagram.name)”: \(error.localizedDescription)")
        }
    }

    func saveFreeformDiagram(_ diagram: FreeformDiagram) {
        freeformDiagrams[diagram.id] = diagram
        let encoder = JSONEncoder()
        let url = diagramsDir.appendingPathComponent("freeform_\(diagram.id.uuidString).json")
        do {
            try encoder.encode(diagram).write(to: url, options: .atomic)
        } catch {
            report("Failed to save diagram “\(diagram.name)”: \(error.localizedDescription)")
        }
    }

    func saveArtifact(_ artifact: CodeArtifact, for codebaseID: UUID) {
        artifacts[codebaseID] = artifact
        let encoder = JSONEncoder()
        let url = artifactsDir.appendingPathComponent("codebase_\(codebaseID.uuidString).json")
        do {
            let stored = StoredArtifact(formatVersion: Self.currentArtifactFormat, artifact: artifact)
            try encoder.encode(stored).write(to: url, options: .atomic)
        } catch {
            report("Failed to save analysis: \(error.localizedDescription)")
        }
    }

    func deleteGeneratedDiagramFile(_ id: UUID) {
        generatedDiagrams.removeValue(forKey: id)
        let url = diagramsDir.appendingPathComponent("generated_\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }

    func deleteFreeformDiagramFile(_ id: UUID) {
        freeformDiagrams.removeValue(forKey: id)
        let url = diagramsDir.appendingPathComponent("freeform_\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }

    func deleteProjectFile(_ id: UUID) {
        let url = projectsDir.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }

    func deleteArtifactFile(for codebaseID: UUID) {
        artifacts.removeValue(forKey: codebaseID)
        let url = artifactsDir.appendingPathComponent("codebase_\(codebaseID.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - GitHub clones

    /// Where a GitHub-backed codebase's synced folder lives (whether or not it exists yet) —
    /// what `Codebase.directoryPath` points at once `githubSource` is set.
    func githubCloneURL(for codebaseID: UUID) -> URL {
        githubClonesDir.appendingPathComponent(codebaseID.uuidString, isDirectory: true)
    }

    /// Removes a GitHub-backed codebase's synced folder, mirroring `deleteArtifactFile`.
    func deleteGitHubClone(for codebaseID: UUID) {
        try? FileManager.default.removeItem(at: githubCloneURL(for: codebaseID))
    }

    // MARK: - Managed quality-check rules

    /// The location of the app-managed YAML rules file for a codebase (whether or not it exists yet).
    func managedRulesURL(forCodebase codebaseID: UUID) -> URL {
        rulesDir.appendingPathComponent("codebase_\(codebaseID.uuidString).yaml")
    }

    /// Whether `path` points at a file the app manages (and so can be edited in the form), as opposed
    /// to an external file the user referenced. Compared on standardized paths so `..`/symlinks in the
    /// stored path don't fool the prefix check.
    func isManaged(path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let resolved = URL(fileURLWithPath: path).standardizedFileURL.path
        let managed = rulesDir.standardizedFileURL.path
        return resolved == managed || resolved.hasPrefix(managed + "/")
    }

    /// Serializes UI-authored rules to the codebase's managed YAML file and returns its URL.
    @discardableResult
    func saveManagedRules(_ rules: QualityRules, forCodebase codebaseID: UUID) throws -> URL {
        let url = managedRulesURL(forCodebase: codebaseID)
        let yaml = try YAMLEncoder().encode(rules)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Decodes the codebase's managed rules file, or `nil` if it doesn't exist yet / can't be read.
    func loadManagedRules(forCodebase codebaseID: UUID) -> QualityRules? {
        let url = managedRulesURL(forCodebase: codebaseID)
        guard let yaml = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return try? YAMLDecoder().decode(QualityRules.self, from: yaml)
    }

    func deleteManagedRules(forCodebase codebaseID: UUID) {
        try? FileManager.default.removeItem(at: managedRulesURL(forCodebase: codebaseID))
    }
}
