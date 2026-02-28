import Foundation
import UMLCore

/// Per-file persistence layout:
/// ```
/// <baseDir>/
///   manifest.json          – array of project IDs
///   projects/
///     <projectID>.json     – Project struct (includes codebases, diagram IDs)
///   diagrams/
///     generated_<diagramID>.json  – GeneratedDiagram
///     custom_<diagramID>.json     – CustomDiagram
///   artifacts/
///     codebase_<codebaseID>.json – CodeArtifact (analysis result)
/// ```
final class ProjectStore: ObservableObject {
    @Published var projects: [Project] = []

    /// In-memory cache of loaded diagrams, keyed by ID.
    @Published var generatedDiagrams: [UUID: GeneratedDiagram] = [:]
    @Published var customDiagrams: [UUID: CustomDiagram] = [:]

    /// In-memory cache of loaded artifacts, keyed by codebase ID.
    @Published var artifacts: [UUID: CodeArtifact] = [:]

    let baseDir: URL
    private var projectsDir: URL { baseDir.appendingPathComponent("projects", isDirectory: true) }
    private var diagramsDir: URL { baseDir.appendingPathComponent("diagrams", isDirectory: true) }
    private var artifactsDir: URL { baseDir.appendingPathComponent("artifacts", isDirectory: true) }
    private var manifestURL: URL { baseDir.appendingPathComponent("manifest.json") }

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
            self.baseDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
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

        guard fileManager.fileExists(atPath: manifestURL.path) else { return }
        do {
            let data = try Data(contentsOf: manifestURL)
            let projectIDs = try decoder.decode([UUID].self, from: data)
            var loaded: [Project] = []
            for id in projectIDs {
                let url = projectsDir.appendingPathComponent("\(id.uuidString).json")
                if fileManager.fileExists(atPath: url.path) {
                    let pData = try Data(contentsOf: url)
                    let project = try decoder.decode(Project.self, from: pData)
                    loaded.append(project)
                    for did in project.generatedDiagramIDs {
                        loadGeneratedDiagram(did)
                    }
                    for did in project.customDiagramIDs {
                        loadCustomDiagram(did)
                    }
                    for codebase in project.codebases where codebase.hasArtifact {
                        loadArtifact(for: codebase.id)
                    }
                }
            }
            projects = loaded
        } catch {
            print("Failed to load manifest: \(error)")
        }
    }

    func loadGeneratedDiagram(_ id: UUID) {
        guard generatedDiagrams[id] == nil else { return }
        let url = diagramsDir.appendingPathComponent("generated_\(id.uuidString).json")
        do {
            let data = try Data(contentsOf: url)
            generatedDiagrams[id] = try JSONDecoder().decode(GeneratedDiagram.self, from: data)
        } catch {
            print("Failed to load generated diagram \(id): \(error)")
        }
    }

    func loadCustomDiagram(_ id: UUID) {
        guard customDiagrams[id] == nil else { return }
        let url = diagramsDir.appendingPathComponent("custom_\(id.uuidString).json")
        do {
            let data = try Data(contentsOf: url)
            customDiagrams[id] = try JSONDecoder().decode(CustomDiagram.self, from: data)
        } catch {
            print("Failed to load custom diagram \(id): \(error)")
        }
    }

    func loadArtifact(for codebaseID: UUID) {
        guard artifacts[codebaseID] == nil else { return }
        let url = artifactsDir.appendingPathComponent("codebase_\(codebaseID.uuidString).json")
        do {
            let data = try Data(contentsOf: url)
            artifacts[codebaseID] = try JSONDecoder().decode(CodeArtifact.self, from: data)
        } catch {
            print("Failed to load artifact for codebase \(codebaseID): \(error)")
        }
    }

    // MARK: - Artifact Access

    func artifact(for codebaseID: UUID) -> CodeArtifact? {
        artifacts[codebaseID]
    }

    // MARK: - Save

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        do {
            let ids = projects.map(\.id)
            try encoder.encode(ids).write(to: manifestURL, options: .atomic)
        } catch {
            print("Failed to save manifest: \(error)")
        }

        for project in projects {
            saveProject(project)
        }
    }

    func saveProject(_ project: Project) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let url = projectsDir.appendingPathComponent("\(project.id.uuidString).json")
        do {
            try encoder.encode(project).write(to: url, options: .atomic)
        } catch {
            print("Failed to save project \(project.id): \(error)")
        }
    }

    func saveGeneratedDiagram(_ diagram: GeneratedDiagram) {
        generatedDiagrams[diagram.id] = diagram
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let url = diagramsDir.appendingPathComponent("generated_\(diagram.id.uuidString).json")
        do {
            try encoder.encode(diagram).write(to: url, options: .atomic)
        } catch {
            print("Failed to save generated diagram \(diagram.id): \(error)")
        }
    }

    func saveCustomDiagram(_ diagram: CustomDiagram) {
        customDiagrams[diagram.id] = diagram
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let url = diagramsDir.appendingPathComponent("custom_\(diagram.id.uuidString).json")
        do {
            try encoder.encode(diagram).write(to: url, options: .atomic)
        } catch {
            print("Failed to save custom diagram \(diagram.id): \(error)")
        }
    }

    func saveArtifact(_ artifact: CodeArtifact, for codebaseID: UUID) {
        artifacts[codebaseID] = artifact
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let url = artifactsDir.appendingPathComponent("codebase_\(codebaseID.uuidString).json")
        do {
            try encoder.encode(artifact).write(to: url, options: .atomic)
        } catch {
            print("Failed to save artifact for codebase \(codebaseID): \(error)")
        }
    }

    func deleteGeneratedDiagramFile(_ id: UUID) {
        generatedDiagrams.removeValue(forKey: id)
        let url = diagramsDir.appendingPathComponent("generated_\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }

    func deleteCustomDiagramFile(_ id: UUID) {
        customDiagrams.removeValue(forKey: id)
        let url = diagramsDir.appendingPathComponent("custom_\(id.uuidString).json")
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
