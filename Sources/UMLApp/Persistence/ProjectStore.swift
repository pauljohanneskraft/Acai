import Foundation

/// Per-file persistence layout:
/// ```
/// <baseDir>/
///   manifest.json          – array of project IDs
///   projects/
///     <projectID>.json     – Project struct (includes codebases, diagram IDs)
///   diagrams/
///     stored_<diagramID>.json   – StoredDiagram
///     custom_<diagramID>.json   – CustomDiagram
/// ```
final class ProjectStore: ObservableObject {
    @Published var projects: [Project] = []

    /// In-memory cache of loaded diagrams, keyed by ID.
    @Published var storedDiagrams: [UUID: StoredDiagram] = [:]
    @Published var customDiagrams: [UUID: CustomDiagram] = [:]

    let baseDir: URL
    private var projectsDir: URL { baseDir.appendingPathComponent("projects", isDirectory: true) }
    private var diagramsDir: URL { baseDir.appendingPathComponent("diagrams", isDirectory: true) }
    private var manifestURL: URL { baseDir.appendingPathComponent("manifest.json") }

    init(baseDir: URL? = nil) {
        let fm = FileManager.default
        if let baseDir {
            self.baseDir = baseDir
        } else {
            #if os(macOS)
            let appSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let bundleID = Bundle.main.bundleIdentifier ?? "UMLApp"
            self.baseDir = (appSupport ?? fm.homeDirectoryForCurrentUser).appendingPathComponent(bundleID, isDirectory: true)
            #else
            self.baseDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
            #endif
        }
        try? fm.createDirectory(at: self.baseDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: diagramsDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Load

    func load() {
        let fm = FileManager.default
        let decoder = JSONDecoder()

        guard fm.fileExists(atPath: manifestURL.path) else { return }
        do {
            let data = try Data(contentsOf: manifestURL)
            let projectIDs = try decoder.decode([UUID].self, from: data)
            var loaded: [Project] = []
            for id in projectIDs {
                let url = projectsDir.appendingPathComponent("\(id.uuidString).json")
                if fm.fileExists(atPath: url.path) {
                    let pData = try Data(contentsOf: url)
                    let project = try decoder.decode(Project.self, from: pData)
                    loaded.append(project)
                    for did in project.storedDiagramIDs {
                        loadStoredDiagram(did)
                    }
                    for did in project.customDiagramIDs {
                        loadCustomDiagram(did)
                    }
                }
            }
            projects = loaded
        } catch {
            print("Failed to load manifest: \(error)")
        }
    }

    func loadStoredDiagram(_ id: UUID) {
        guard storedDiagrams[id] == nil else { return }
        let url = diagramsDir.appendingPathComponent("stored_\(id.uuidString).json")
        do {
            let data = try Data(contentsOf: url)
            storedDiagrams[id] = try JSONDecoder().decode(StoredDiagram.self, from: data)
        } catch {
            print("Failed to load stored diagram \(id): \(error)")
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

    func saveStoredDiagram(_ diagram: StoredDiagram) {
        storedDiagrams[diagram.id] = diagram
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let url = diagramsDir.appendingPathComponent("stored_\(diagram.id.uuidString).json")
        do {
            try encoder.encode(diagram).write(to: url, options: .atomic)
        } catch {
            print("Failed to save stored diagram \(diagram.id): \(error)")
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

    func deleteStoredDiagramFile(_ id: UUID) {
        storedDiagrams.removeValue(forKey: id)
        let url = diagramsDir.appendingPathComponent("stored_\(id.uuidString).json")
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
}

