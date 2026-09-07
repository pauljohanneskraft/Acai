import Foundation
import AcaiGit
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
@MainActor
final class ProjectStore: ObservableObject {
    @Published var projects: [Project] = []
    @Published var generatedDiagrams: [UUID: GeneratedDiagram] = [:]
    @Published var freeformDiagrams: [UUID: FreeformDiagram] = [:]
    @Published var artifacts: [UUID: CodeArtifact] = [:]
    @Published var recentlyViewed = RecentlyViewed()

    /// The most recent load/save failure, surfaced to the UI (e.g. via an alert).
    @Published var lastError: StoreError?

    /// A user-presentable persistence error. `Identifiable` so SwiftUI `.alert(item:)` can bind it.
    struct StoreError: Identifiable {
        let id = UUID()
        let message: String
        /// Set when the failure was "this codebase's folder can't be reached", which the user can
        /// fix by pointing it at another folder — the alert then offers that instead of just "OK".
        var relocatableCodebaseID: UUID?
    }

    func report(_ message: LocalizedStringResource, relocating codebaseID: UUID? = nil) {
        report(String(localized: message), relocating: codebaseID)
    }

    /// The `String` overload carries text the app did not write — an engine or system error's own
    /// `localizedDescription`, which is shown untranslated rather than guessed at.
    func report(_ message: String, relocating codebaseID: UUID? = nil) {
        print(message)
        lastError = StoreError(message: message, relocatableCodebaseID: codebaseID)
    }

    let baseDir: URL
    private var projectsDir: URL { baseDir.appendingPathComponent("projects", isDirectory: true) }
    private var diagramsDir: URL { baseDir.appendingPathComponent("diagrams", isDirectory: true) }
    private var artifactsDir: URL { baseDir.appendingPathComponent("artifacts", isDirectory: true) }
    /// A check whose `rulesPath` resolves inside this directory is "managed" — editable in the
    /// form; any other path is an external file the user referenced.
    private var rulesDir: URL { baseDir.appendingPathComponent("rules", isDirectory: true) }
    /// GitHub-backed codebases created before worktree support existed only — newer codebases use
    /// `gitRepositoriesDir`/`gitWorktreesDir` instead.
    var githubClonesDir: URL { baseDir.appendingPathComponent("github-clones", isDirectory: true) }
    /// One shared "hub" clone per distinct remote URL, reused by every codebase referencing it
    /// instead of each getting an independent full clone.
    var gitRepositoriesDir: URL { baseDir.appendingPathComponent("git-repositories", isDirectory: true) }
    /// One linked-worktree checkout per repository-backed codebase.
    var gitWorktreesDir: URL { baseDir.appendingPathComponent("git-worktrees", isDirectory: true) }
    /// One instance for this store's entire lifetime; a fresh instance would provide no exclusion
    /// against this one.
    let gitRepositoryLocks = GitRepositoryLocks()
    let activityCenter = ActivityCenter()
    private var recentlyViewedURL: URL { baseDir.appendingPathComponent("recentlyViewed.json") }

    init(baseDir: URL? = nil) {
        let fileManager = FileManager.default
        if let baseDir {
            self.baseDir = baseDir
        } else if let fixtureBaseDir = UITestFixtureResolver().resolveBaseDir() {
            self.baseDir = fixtureBaseDir
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
        try? fileManager.createDirectory(at: gitRepositoriesDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: gitWorktreesDir, withIntermediateDirectories: true)
        load()
        loadRecentlyViewed()
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
                    let name = projectURL.lastPathComponent
                    report(.app("Error.ProjectStore.LoadProject \(name) \(error.localizedDescription)"))
                }
            }
        } catch {
            report(.app("Error.ProjectStore.LoadProjectDirectory \(error.localizedDescription)"))
        }
    }

    func loadGeneratedDiagram(_ id: UUID) {
        guard generatedDiagrams[id] == nil else { return }
        let url = diagramsDir.appendingPathComponent("generated_\(id.uuidString).json")
        do {
            let data = try Data(contentsOf: url)
            generatedDiagrams[id] = try JSONDecoder().decode(GeneratedDiagram.self, from: data)
        } catch {
            report(.app("Error.ProjectStore.LoadGeneratedDiagram \(error.localizedDescription)"))
        }
    }

    func loadFreeformDiagram(_ id: UUID) {
        guard freeformDiagrams[id] == nil else { return }
        let url = diagramsDir.appendingPathComponent("freeform_\(id.uuidString).json")
        do {
            let data = try Data(contentsOf: url)
            freeformDiagrams[id] = try JSONDecoder().decode(FreeformDiagram.self, from: data)
        } catch {
            report(.app("Error.ProjectStore.LoadFreeformDiagram \(error.localizedDescription)"))
        }
    }

    /// Versioned envelope around a persisted `CodeArtifact`. Bumping ``currentArtifactFormat`` makes
    /// `loadArtifact` treat older stored analyses as stale so the UI offers Reindex. v2 persists the
    /// semantic (un-flattened) artifact so nesting-depth metrics are correct; v1 stored the
    /// display-flattened form and read nesting as 0.
    private struct StoredArtifact: Codable {
        var formatVersion: Int
        var artifact: CodeArtifact
    }

    /// Current on-disk artifact format. A lower version — or a pre-envelope bare `CodeArtifact`
    /// (fails to decode as ``StoredArtifact``) — is dropped back to "not indexed".
    private static let currentArtifactFormat = 2

    func loadArtifact(for codebaseID: UUID) {
        guard artifacts[codebaseID] == nil else { return }
        let url = artifactsDir.appendingPathComponent("codebase_\(codebaseID.uuidString).json")
        do {
            let data = try Data(contentsOf: url)
            let stored = try JSONDecoder().decode(StoredArtifact.self, from: data)
            guard stored.formatVersion >= Self.currentArtifactFormat else {
                markCodebaseNotIndexed(codebaseID)
                return
            }
            artifacts[codebaseID] = stored.artifact
        } catch is DecodingError {
            // Predates the versioned envelope, or a schema change — treat as never indexed so the
            // UI offers Reindex rather than a decode error the user can't act on.
            markCodebaseNotIndexed(codebaseID)
        } catch {
            report(.app("Error.ProjectStore.LoadStoredAnalysis \(error.localizedDescription)"))
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
            report(.app("Error.ProjectStore.SaveProject \(project.title) \(error.localizedDescription)"))
        }
    }

    func saveGeneratedDiagram(_ diagram: GeneratedDiagram) {
        generatedDiagrams[diagram.id] = diagram
        let encoder = JSONEncoder()
        let url = diagramsDir.appendingPathComponent("generated_\(diagram.id.uuidString).json")
        do {
            try encoder.encode(diagram).write(to: url, options: .atomic)
        } catch {
            report(.app("Error.ProjectStore.SaveDiagram \(diagram.name) \(error.localizedDescription)"))
        }
    }

    func saveFreeformDiagram(_ diagram: FreeformDiagram) {
        freeformDiagrams[diagram.id] = diagram
        let encoder = JSONEncoder()
        let url = diagramsDir.appendingPathComponent("freeform_\(diagram.id.uuidString).json")
        do {
            try encoder.encode(diagram).write(to: url, options: .atomic)
        } catch {
            report(.app("Error.ProjectStore.SaveDiagram \(diagram.name) \(error.localizedDescription)"))
        }
    }

    /// Updates the in-memory artifact immediately, then encodes and writes it to disk off the main
    /// actor — for a large codebase, JSON encode + atomic write can visibly stall the UI if done
    /// inline. Fire-and-forget; callers that need "saved" to be a real completion signal (not just a
    /// side effect) use `saveArtifactAndWait` instead.
    func saveArtifact(_ artifact: CodeArtifact, for codebaseID: UUID) {
        artifacts[codebaseID] = artifact
        Task {
            do {
                try await writeArtifactToDisk(artifact, for: codebaseID)
            } catch {
                report(.app("Error.ProjectStore.SaveAnalysis \(error.localizedDescription)"))
            }
        }
    }

    func saveArtifactAndWait(_ artifact: CodeArtifact, for codebaseID: UUID) async throws {
        artifacts[codebaseID] = artifact
        try await writeArtifactToDisk(artifact, for: codebaseID)
    }

    private func writeArtifactToDisk(_ artifact: CodeArtifact, for codebaseID: UUID) async throws {
        let url = artifactsDir.appendingPathComponent("codebase_\(codebaseID.uuidString).json")
        let stored = StoredArtifact(formatVersion: Self.currentArtifactFormat, artifact: artifact)
        try await Task.detached(priority: .utility) {
            try JSONEncoder().encode(stored).write(to: url, options: .atomic)
        }.value
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

    // MARK: - Recently Viewed

    func loadRecentlyViewed() {
        guard let data = try? Data(contentsOf: recentlyViewedURL) else { return }
        recentlyViewed = (try? JSONDecoder().decode(RecentlyViewed.self, from: data)) ?? RecentlyViewed()
    }

    func saveRecentlyViewed() {
        do {
            try JSONEncoder().encode(recentlyViewed).write(to: recentlyViewedURL, options: .atomic)
        } catch {
            report(.app("Error.ProjectStore.SaveRecentlyViewed \(error.localizedDescription)"))
        }
    }

    func recordOpened(_ item: RecentlyViewedItem) {
        recentlyViewed.recordOpened(item)
        saveRecentlyViewed()
    }

    func togglePin(_ item: RecentlyViewedItem) {
        recentlyViewed.togglePin(item)
        saveRecentlyViewed()
    }

    func removeFromRecentlyViewed(_ item: RecentlyViewedItem) {
        recentlyViewed.remove(item)
        saveRecentlyViewed()
    }

    // MARK: - GitHub clones (older codebases only — see `githubClonesDir`)

    func githubCloneURL(for codebaseID: UUID) -> URL {
        githubClonesDir.appendingPathComponent(codebaseID.uuidString, isDirectory: true)
    }

    func deleteGitHubClone(for codebaseID: UUID) {
        try? FileManager.default.removeItem(at: githubCloneURL(for: codebaseID))
    }

    // MARK: - Git worktrees

    /// Stable and unique per codebase, so it can't collide with a branch/worktree name a user
    /// might otherwise pick.
    func gitWorktreeName(for codebaseID: UUID) -> String {
        "codebase-\(codebaseID.uuidString)"
    }

    func gitWorktreeURL(for codebaseID: UUID) -> URL {
        gitWorktreesDir.appendingPathComponent(codebaseID.uuidString, isDirectory: true)
    }

    // MARK: - Managed quality-check rules

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

    @discardableResult
    func saveManagedRules(_ rules: QualityRules, forCodebase codebaseID: UUID) throws -> URL {
        let url = managedRulesURL(forCodebase: codebaseID)
        let yaml = try YAMLEncoder().encode(rules)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func loadManagedRules(forCodebase codebaseID: UUID) -> QualityRules? {
        let url = managedRulesURL(forCodebase: codebaseID)
        guard let yaml = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return try? YAMLDecoder().decode(QualityRules.self, from: yaml)
    }

    func deleteManagedRules(forCodebase codebaseID: UUID) {
        try? FileManager.default.removeItem(at: managedRulesURL(forCodebase: codebaseID))
    }
}
