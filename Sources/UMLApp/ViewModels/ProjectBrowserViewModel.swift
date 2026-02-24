import Foundation
import SwiftUI
import UMLLibrary
import UMLCore
import UMLDiagram

@MainActor
final class ProjectBrowserViewModel: ObservableObject {
    @Published var store: ProjectStore
    @Published var selection: Selection? = nil
    
    enum Selection: Hashable {
        case project(UUID)
        case codebase(UUID)
        case diagram(UUID) // View class diagram for a codebase
    }
    
    init(store: ProjectStore = ProjectStore()) {
        self.store = store
    }
    
    func addProject(title: String, subtitle: String, iconSystemName: String) {
        let project = Project(title: title, subtitle: subtitle, iconSystemName: iconSystemName, codebases: [])
        store.projects.append(project)
        store.save()
    }
    
    func addCodebase(to projectID: UUID, name: String, directoryURL: URL) {
        guard let idx = store.projects.firstIndex(where: { $0.id == projectID }) else { return }
        var project = store.projects[idx]
        let codebase = Codebase(name: name, directoryPath: directoryURL.path, artifact: nil, languages: [], lastIndexed: nil)
        project.codebases.append(codebase)
        store.projects[idx] = project
        store.save()
    }
    
    func removeProject(_ projectID: UUID) {
        store.projects.removeAll { $0.id == projectID }
        store.save()
    }
    
    func removeCodebase(_ codebaseID: UUID) {
        for i in store.projects.indices {
            store.projects[i].codebases.removeAll { $0.id == codebaseID }
        }
        store.save()
    }
    
    func reindex(codebaseID: UUID) async {
        guard let pIndex = store.projects.firstIndex(where: { $0.id == projectID(for: codebaseID) }),
              let cIndex = store.projects[pIndex].codebases.firstIndex(where: { $0.id == codebaseID }) else { return }
        var codebase = store.projects[pIndex].codebases[cIndex]
        let url = URL(fileURLWithPath: codebase.directoryPath).standardizedFileURL

        do {
            let artifact = try await Task.detached(priority: .userInitiated) {
                try AnalysisService.shared.analyzeProject(at: url, allowedLanguages: [])
            }.value
            codebase.artifact = artifact
            codebase.lastIndexed = Date()
            store.projects[pIndex].codebases[cIndex] = codebase
            store.save()
            objectWillChange.send()
        } catch {
            print("Reindex failed: \(error)")
        }
    }
    
    func generateDOT(for codebaseID: UUID) -> String {
        guard let codebase = codebase(for: codebaseID) else { return "digraph UML { }" }
        let url = URL(fileURLWithPath: codebase.directoryPath).standardizedFileURL

        if let artifact = codebase.artifact {
            return DOTGenerator().generate(from: artifact)
        }

        // If no cached artifact, attempt an on-the-fly analysis.
        if let artifact = try? AnalysisService.shared.analyzeProject(at: url, allowedLanguages: []) {
            return DOTGenerator().generate(from: artifact)
        }

        return "digraph UML { label=\"No analysis available\" }"
    }
    
    func exportDOT(for codebaseID: UUID) {
        let dot = generateDOT(for: codebaseID)
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["dot"]
        panel.nameFieldStringValue = "\(codebase(for: codebaseID)?.name ?? "diagram").dot"
        if panel.runModal() == .OK, let url = panel.url {
            do { try dot.data(using: .utf8)?.write(to: url, options: .atomic) } catch { print("Export failed: \(error)") }
        }
        #endif
    }
    
    // Helpers
    private func projectID(for codebaseID: UUID) -> UUID? {
        for p in store.projects where p.codebases.contains(where: { $0.id == codebaseID }) { return p.id }
        return nil
    }
    private func codebase(for codebaseID: UUID) -> Codebase? {
        for p in store.projects { if let c = p.codebases.first(where: { $0.id == codebaseID }) { return c } }
        return nil
    }
}

