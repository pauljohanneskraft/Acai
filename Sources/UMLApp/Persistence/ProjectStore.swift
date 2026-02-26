import Foundation

final class ProjectStore: ObservableObject {
    @Published var projects: [Project] = []
    @Published var globalCustomDiagrams: [CustomDiagram] = []
    private let fileURL: URL
    private var globalFileURL: URL { fileURL.deletingLastPathComponent().appendingPathComponent("global_diagrams.json") }
    
    init(fileURL: URL? = nil) {
        let fm = FileManager.default
        let base: URL
        if let fileURL {
            base = fileURL.deletingLastPathComponent()
            self.fileURL = fileURL
        } else {
            #if os(macOS)
            let appSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let bundleID = Bundle.main.bundleIdentifier ?? "UMLApp"
            base = (appSupport ?? fm.homeDirectoryForCurrentUser).appendingPathComponent(bundleID, isDirectory: true)
            #else
            base = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
            #endif
            self.fileURL = base.appendingPathComponent("projects.json")
        }
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        load()
    }
    
    func load() {
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let decoded = try JSONDecoder().decode([Project].self, from: data)
                projects = decoded
            } catch {
                print("Failed to load projects: \(error)")
            }
        }
        if fm.fileExists(atPath: globalFileURL.path) {
            do {
                let data = try Data(contentsOf: globalFileURL)
                globalCustomDiagrams = try JSONDecoder().decode([CustomDiagram].self, from: data)
            } catch {
                print("Failed to load global diagrams: \(error)")
            }
        }
    }
    
    func save() {
        do {
            let data = try JSONEncoder().encode(projects)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("Failed to save projects: \(error)")
        }
        do {
            let data = try JSONEncoder().encode(globalCustomDiagrams)
            try data.write(to: globalFileURL, options: [.atomic])
        } catch {
            print("Failed to save global diagrams: \(error)")
        }
    }
}

