import Foundation

final class ProjectStore: ObservableObject {
    @Published var projects: [Project] = []
    private let fileURL: URL
    
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
        guard fm.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([Project].self, from: data)
            projects = decoded
        } catch {
            print("Failed to load projects: \(error)")
        }
    }
    
    func save() {
        do {
            let data = try JSONEncoder().encode(projects)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("Failed to save projects: \(error)")
        }
    }
}

