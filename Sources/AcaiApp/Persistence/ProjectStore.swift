import Combine
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
/// ```
/// A codebase's own analysis result lives in `AcaiCore.AnalysisStore` — `~/.acai/analysis`, shared
/// with the CLI and an MCP session over the same directory — keyed by the codebase's resolved
/// `directoryPath` rather than its id.
@MainActor
final class ProjectStore: ObservableObject {
    /// The one store every window and system action of the running app shares.
    static let app = ProjectStore()

    @Published var projects: [Project] = []
    @Published var generatedDiagrams: [UUID: GeneratedDiagram] = [:]
    @Published var freeformDiagrams: [UUID: FreeformDiagram] = [:]
    @Published var artifacts: [UUID: CodeArtifact] = [:]

    /// The most recent load/save failure, surfaced to the UI (e.g. via an alert).
    @Published var lastError: StoreError?

    private var fixturePreindexing: Task<Void, Never>?

    /// A user-presentable persistence error. `Identifiable` so SwiftUI `.alert(item:)` can bind it.
    struct StoreError: Identifiable {
        /// The cause, separate from the presented `message`, so a caller can act on it.
        enum Reason: Equatable, Sendable {
            /// The codebase's folder is gone, moved, or refused by the sandbox.
            case codebaseUnreachable
            case indexingFailed
            case other
        }

        let id = UUID()
        let message: String
        var reason: Reason = .other
        /// Set when the failure was "this codebase's folder can't be reached", which the user can
        /// fix by pointing it at another folder — the alert then offers that instead of just "OK".
        var relocatableCodebaseID: UUID?
    }

    func report(
        _ message: LocalizedStringResource, reason: StoreError.Reason = .other, relocating codebaseID: UUID? = nil
    ) {
        report(String(localized: message), reason: reason, relocating: codebaseID)
    }

    /// The `String` overload carries text the app did not write — an engine or system error's own
    /// `localizedDescription`, which is shown untranslated rather than guessed at.
    func report(_ message: String, reason: StoreError.Reason = .other, relocating codebaseID: UUID? = nil) {
        print(message)
        lastError = StoreError(message: message, reason: reason, relocatableCodebaseID: codebaseID)
    }

    /// Codebases the app cloned from GitHub — the ones the signed-in account's token reaches.
    var gitHubBackedCodebaseCount: Int {
        projects.flatMap(\.codebases).filter { codebase in
            guard codebase.managedCheckout != nil, case .github = codebase.repository?.host else { return false }
            return true
        }.count
    }

    let baseDir: URL
    /// Writes generated diagrams, coalescing bursts. Injectable so a test can count writes and
    /// shorten the debounce.
    let diagramWriter: DebouncedDiagramWriter
    /// The shared analysis store an artifact is read from and written to — `AnalysisStore.standard`
    /// (`~/.acai/analysis`) in production, shared with the CLI and an MCP session over the same
    /// directory. Injectable so a test's writes never reach the real store.
    let analysisStore: AnalysisStore
    /// `nil` by default over an explicit `baseDir`, so a test never writes the real App Group container.
    let widgetPublisher: CodebaseWidgetPublisher?
    private var projectsDir: URL { baseDir.appendingPathComponent("projects", isDirectory: true) }
    // Not `private`: `ProjectStore+DiagramFiles.swift`'s extension needs it too — same "not private,
    // another file's extension needs it too" pattern used throughout this app.
    var diagramsDir: URL { baseDir.appendingPathComponent("diagrams", isDirectory: true) }
    /// A check whose `rulesPath` resolves inside this directory is "managed" — editable in the
    /// form; any other path is an external file the user referenced.
    var rulesDir: URL { baseDir.appendingPathComponent("rules", isDirectory: true) }
    /// One shared "hub" clone per distinct remote URL, reused by every codebase referencing it
    /// instead of each getting an independent full clone.
    var gitRepositoriesDir: URL { baseDir.appendingPathComponent("git-repositories", isDirectory: true) }
    /// One linked-worktree checkout per repository-backed codebase.
    var gitWorktreesDir: URL { baseDir.appendingPathComponent("git-worktrees", isDirectory: true) }
    /// One instance for this store's entire lifetime; a fresh instance would provide no exclusion
    /// against this one.
    let gitRepositoryLocks = GitRepositoryLocks()
    let activityCenter = ActivityCenter()
    /// Codebases whose cached analysis every window must drop.
    let analysisInvalidations = PassthroughSubject<UUID, Never>()
    /// Remotes whose hub clone changed on disk (a worktree attached or removed, history deepened),
    /// which `projects` alone doesn't show since the git work finishes after the store changes.
    let repositoryChanges = PassthroughSubject<URL, Never>()

    init(
        baseDir: URL? = nil, analysisStore: AnalysisStore = .standard,
        diagramWriter: DebouncedDiagramWriter = DebouncedDiagramWriter(),
        widgetPublisher: CodebaseWidgetPublisher? = nil
    ) {
        self.analysisStore = analysisStore
        self.diagramWriter = diagramWriter
        let fileManager = FileManager.default
        if let baseDir {
            self.baseDir = baseDir
            self.widgetPublisher = widgetPublisher
        } else if let fixtureBaseDir = UITestFixtureResolver().resolveBaseDir() {
            self.baseDir = fixtureBaseDir
            self.widgetPublisher = CodebaseWidgetPublisher(
                store: CodebaseWidgetSnapshotStore(containerURL: fixtureBaseDir.appendingPathComponent("widget")))
        } else {
            self.widgetPublisher = widgetPublisher ?? CodebaseWidgetPublisher()
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
        try? fileManager.createDirectory(at: rulesDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: gitRepositoriesDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: gitWorktreesDir, withIntermediateDirectories: true)
        load()
        let gitStorageSweep = GitStorageSweep(store: self)
        if !gitStorageSweep.isEmpty {
            Task.detached(priority: .utility) { await gitStorageSweep.run() }
        }
    }

    // MARK: - Load

    func load() {
        let fileManager = FileManager.default
        let decoder = JSONDecoder()
        var fixtures: [FixturePreindex] = []

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
                    fixtures += fixturesToPreindex(inProjectAt: projects.count - 1)
                    for codebase in projects[projects.count - 1].codebases where codebase.hasArtifact {
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
        if !fixtures.isEmpty {
            startFixturePreindexing(fixtures)
        }
    }

    /// Every artifact write awaits this first, so a real index always lands after the canned one.
    func startFixturePreindexing(_ fixtures: [FixturePreindex]) {
        fixturePreindexing = Task { [weak self] in
            for fixture in fixtures {
                await self?.preindex(fixture)
            }
        }
    }

    private func fixturesToPreindex(inProjectAt projectIndex: Int) -> [FixturePreindex] {
        guard let artifactURL = UITestFixtureResolver().resolvePreindexedArtifactURL(),
              let data = try? Data(contentsOf: artifactURL),
              let artifact = try? JSONDecoder().decode(CodeArtifact.self, from: data)
        else { return [] }
        let projectID = projects[projectIndex].id
        return projects[projectIndex].codebases.filter { !$0.hasArtifact }.map { codebase in
            FixturePreindex(
                codebaseID: codebase.id, projectID: projectID,
                sourcePath: codebase.directoryPath.resolvedAsAnalysisSourcePath, artifact: artifact
            )
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

    /// The shared analysis store (`AcaiCore.AnalysisStore`) is the only source of an artifact — the
    /// CLI and an MCP session over the same directory read and write it too. A codebase with no entry
    /// there reads as never indexed, so the UI offers Reindex.
    func loadArtifact(for codebaseID: UUID) {
        guard artifacts[codebaseID] == nil else { return }
        guard let sourcePath = resolvedSourcePath(for: codebaseID),
              case .entry(let entry) = analysisStore.lookup(forResolvedPath: sourcePath)
        else {
            markCodebaseNotIndexed(codebaseID)
            return
        }
        guard !rejectingUnsupportedSchema(of: entry.artifact, for: codebaseID) else { return }
        artifacts[codebaseID] = entry.artifact
    }

    /// `true` when `artifact`'s schema is too new for this build to read — reports the specific
    /// error, naming both versions, and drops the codebase back to "not indexed" so Reindex is
    /// offered rather than showing a stale or partially-misread analysis.
    private func rejectingUnsupportedSchema(of artifact: CodeArtifact, for codebaseID: UUID) -> Bool {
        let found = artifact.schemaVersion
        guard found > CodeArtifact.currentSchemaVersion else { return false }
        let expected = CodeArtifact.currentSchemaVersion
        report(.app("Error.ProjectStore.UnsupportedArtifactSchema \(found) \(expected)"))
        markCodebaseNotIndexed(codebaseID)
        return true
    }

    /// The standardized, symlink-resolved absolute path `AnalysisStore` keys entries on, for the
    /// directory a codebase currently points at. `nil` once the codebase itself is gone.
    private func resolvedSourcePath(for codebaseID: UUID) -> String? {
        for project in projects {
            if let codebase = project.codebases.first(where: { $0.id == codebaseID }) {
                return codebase.directoryPath.resolvedAsAnalysisSourcePath
            }
        }
        return nil
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
        await fixturePreindexing?.value
        guard let sourcePath = resolvedSourcePath(for: codebaseID) else {
            throw StoreCodebaseNotFoundError()
        }
        let store = analysisStore
        try await Task.detached(priority: .utility) {
            let fingerprint = CodebaseFreshnessChecker(directoryPath: sourcePath).currentFingerprint()
            try store.write(artifact, sourcePath: sourcePath, fingerprint: fingerprint)
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

    /// `directoryPath` is required once the codebase itself may already be gone from `projects`
    /// (as it is when called from `deleteCodebaseData`, after removal) — otherwise the shared
    /// store's entry can no longer be found by resolved path.
    func deleteArtifactFile(for codebaseID: UUID, directoryPath: String? = nil) {
        artifacts.removeValue(forKey: codebaseID)
        let sourcePath = directoryPath?.resolvedAsAnalysisSourcePath ?? resolvedSourcePath(for: codebaseID)
        if let sourcePath {
            try? analysisStore.removeEntry(forResolvedPath: sourcePath)
        }
    }

    // MARK: - Codebase removal

    /// Removes the codebase from the project together with its generated diagrams, stored analysis
    /// and managed rules. The caller persists the project.
    func deleteCodebaseData(_ codebaseID: UUID, fromProjectAt projectIndex: Int) {
        let directoryPath = projects[projectIndex].codebases.first { $0.id == codebaseID }?.directoryPath
        projects[projectIndex].codebases.removeAll { $0.id == codebaseID }
        let orphanedDiagramIDs = projects[projectIndex].generatedDiagramIDs.filter {
            generatedDiagrams[$0]?.codebaseID == codebaseID
        }
        projects[projectIndex].generatedDiagramIDs.removeAll { orphanedDiagramIDs.contains($0) }
        orphanedDiagramIDs.forEach(deleteGeneratedDiagramFile)
        deleteArtifactFile(for: codebaseID, directoryPath: directoryPath)
        deleteManagedRules(forCodebase: codebaseID)
    }

}

/// Thrown by `ProjectStore.writeArtifactToDisk` when the codebase an analysis is being saved for
/// no longer exists — saving races a deletion, so there is nowhere left to resolve a source path.
private struct StoreCodebaseNotFoundError: LocalizedError {
    var errorDescription: String? { "This codebase no longer exists, so its analysis could not be saved." }
}

extension String {
    /// The standardized, symlink-resolved absolute path `AnalysisStore` keys an entry on, treating
    /// this string as a directory path.
    fileprivate var resolvedAsAnalysisSourcePath: String {
        URL(fileURLWithPath: self).standardizedFileURL.resolvingSymlinksInPath().path
    }
}
