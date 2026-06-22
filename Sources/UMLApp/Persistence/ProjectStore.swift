import Foundation
import UMLCore

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
            let bundleID = Bundle.main.bundleIdentifier ?? "UMLApp"
            self.baseDir = (appSupport ?? fileManager.homeDirectoryForCurrentUser)
                .appendingPathComponent(bundleID, isDirectory: true)
            #else
            self.baseDir = (fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory)
                .appendingPathComponent("UMLApp", isDirectory: true)
            #endif
        }
        try? fileManager.createDirectory(at: self.baseDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: diagramsDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: artifactsDir, withIntermediateDirectories: true)
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

    func loadArtifact(for codebaseID: UUID) {
        guard artifacts[codebaseID] == nil else { return }
        let url = artifactsDir.appendingPathComponent("codebase_\(codebaseID.uuidString).json")
        do {
            let data = try Data(contentsOf: url)
            artifacts[codebaseID] = try JSONDecoder().decode(CodeArtifact.self, from: data)
        } catch {
            report("Failed to load a stored analysis: \(error.localizedDescription)")
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
            try encoder.encode(artifact).write(to: url, options: .atomic)
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
}
