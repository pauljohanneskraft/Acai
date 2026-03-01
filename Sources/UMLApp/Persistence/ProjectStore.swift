import Foundation
import UMLCore

/// Per-file persistence layout:
/// ```
/// <baseDir>/
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
                    for diagramID in project.customDiagramIDs {
                        loadCustomDiagram(diagramID)
                    }
                    for codebase in project.codebases where codebase.hasArtifact {
                        loadArtifact(for: codebase.id)
                    }
                } catch {
                    print("Failed to load project at \(projectURL): \(error)")
                }
            }
        } catch {
            print("Failed to load project directory: \(error)")
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
        for project in projects {
            saveProject(project)
        }
        for diagram in generatedDiagrams.values {
            saveGeneratedDiagram(diagram)
        }
        for diagram in customDiagrams.values {
            saveCustomDiagram(diagram)
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
            print("Failed to save project \(project.id): \(error)")
        }
    }

    func saveGeneratedDiagram(_ diagram: GeneratedDiagram) {
        generatedDiagrams[diagram.id] = diagram
        let encoder = JSONEncoder()
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
