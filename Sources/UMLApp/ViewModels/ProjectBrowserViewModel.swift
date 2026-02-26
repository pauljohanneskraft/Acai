import Foundation
import SwiftUI
import UMLLibrary
import UMLCore
import UMLDiagram

@MainActor
final class ProjectBrowserViewModel: ObservableObject {
    @Published var store: ProjectStore
    @Published var selection: Selection? = nil
    /// The ID of the item whose inspector is shown in the right sidebar.
    @Published var inspectedCodebaseID: UUID? = nil
    @Published var showInspector: Bool = false
    
    enum Selection: Hashable {
        case project(UUID)
        case codebase(UUID)
        case diagram(UUID) // View a stored diagram by its ID
        case customDiagram(UUID) // View a custom diagram by its ID
        case globalDiagrams // Shows the global diagrams list
    }
    
    init(store: ProjectStore = ProjectStore()) {
        self.store = store
    }
    
    /// Persists the store to disk and notifies SwiftUI observers.
    /// Because `store` is a reference type, mutating its `projects` array
    /// does not trigger `@Published`; we must send `objectWillChange` manually.
    private func persistChanges() {
        store.save()
        objectWillChange.send()
    }
    
    // MARK: - Project CRUD
    
    func addProject(title: String, subtitle: String, iconSystemName: String) {
        let project = Project(title: title, subtitle: subtitle, iconSystemName: iconSystemName, codebases: [])
        store.projects.append(project)
        persistChanges()
    }
    
    func updateProject(id: UUID, title: String, subtitle: String, iconSystemName: String) {
        guard let idx = store.projects.firstIndex(where: { $0.id == id }) else { return }
        store.projects[idx].title = title
        store.projects[idx].subtitle = subtitle
        store.projects[idx].iconSystemName = iconSystemName
        persistChanges()
    }
    
    func removeProject(_ projectID: UUID) {
        store.projects.removeAll { $0.id == projectID }
        persistChanges()
    }
    
    // MARK: - Codebase CRUD
    
    func addCodebase(to projectID: UUID, name: String, directoryURL: URL) {
        guard let idx = store.projects.firstIndex(where: { $0.id == projectID }) else { return }
        var project = store.projects[idx]
        let codebase = Codebase(name: name, directoryPath: directoryURL.path, artifact: nil, languages: [], lastIndexed: nil)
        project.codebases.append(codebase)
        store.projects[idx] = project
        persistChanges()
    }
    
    func updateCodebase(id: UUID, name: String) {
        for i in store.projects.indices {
            if let j = store.projects[i].codebases.firstIndex(where: { $0.id == id }) {
                store.projects[i].codebases[j].name = name
                persistChanges()
                return
            }
        }
    }
    
    func removeCodebase(_ codebaseID: UUID) {
        for i in store.projects.indices {
            store.projects[i].codebases.removeAll { $0.id == codebaseID }
            // Also remove stored diagrams linked to this codebase.
            store.projects[i].storedDiagrams.removeAll { $0.codebaseID == codebaseID }
        }
        persistChanges()
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
            persistChanges()
        } catch {
            print("Reindex failed: \(error)")
        }
    }
    
    // MARK: - Stored Diagram CRUD
    
    func addStoredDiagram(to projectID: UUID, codebaseID: UUID, name: String, type: DiagramType, configuration: DiagramConfiguration) -> UUID? {
        guard let idx = store.projects.firstIndex(where: { $0.id == projectID }) else { return nil }
        let diagram = StoredDiagram(name: name, type: type, codebaseID: codebaseID, configuration: configuration)
        store.projects[idx].storedDiagrams.append(diagram)
        persistChanges()
        return diagram.id
    }
    
    func updateStoredDiagramPositions(diagramID: UUID, positions: [String: CGPoint], sizes: [String: CGSize] = [:], scale: CGFloat, offset: CGPoint) {
        for i in store.projects.indices {
            if let j = store.projects[i].storedDiagrams.firstIndex(where: { $0.id == diagramID }) {
                var diagram = store.projects[i].storedDiagrams[j]
                diagram.nodePositions = positions.mapValues { StoredNodePosition(point: $0) }
                if !sizes.isEmpty {
                    diagram.nodeSizes = sizes.mapValues { StoredNodeSize(size: $0) }
                }
                diagram.canvasScale = Double(scale)
                diagram.canvasOffsetX = Double(offset.x)
                diagram.canvasOffsetY = Double(offset.y)
                diagram.lastModified = Date()
                store.projects[i].storedDiagrams[j] = diagram
                persistChanges()
                return
            }
        }
    }
    
    func updateStoredDiagramConfiguration(diagramID: UUID, configuration: DiagramConfiguration) {
        for i in store.projects.indices {
            if let j = store.projects[i].storedDiagrams.firstIndex(where: { $0.id == diagramID }) {
                store.projects[i].storedDiagrams[j].configuration = configuration
                store.projects[i].storedDiagrams[j].lastModified = Date()
                persistChanges()
                return
            }
        }
    }
    
    func removeStoredDiagram(_ diagramID: UUID) {
        for i in store.projects.indices {
            store.projects[i].storedDiagrams.removeAll { $0.id == diagramID }
        }
        persistChanges()
    }
    
    func storedDiagram(for diagramID: UUID) -> StoredDiagram? {
        for p in store.projects {
            if let d = p.storedDiagrams.first(where: { $0.id == diagramID }) { return d }
        }
        return nil
    }
    
    // MARK: - Custom Diagram CRUD
    
    func addCustomDiagram(to projectID: UUID, name: String, type: DiagramType) -> UUID? {
        guard let idx = store.projects.firstIndex(where: { $0.id == projectID }) else { return nil }
        var diagram = CustomDiagram(name: name, diagramType: type)
        diagram.ownerProjectID = projectID
        store.projects[idx].customDiagrams.append(diagram)
        persistChanges()
        return diagram.id
    }
    
    func addGlobalCustomDiagram(name: String, type: DiagramType) -> UUID {
        var diagram = CustomDiagram(name: name, diagramType: type)
        diagram.ownerProjectID = nil
        diagram.ownerCodebaseID = nil
        store.globalCustomDiagrams.append(diagram)
        persistChanges()
        return diagram.id
    }
    
    func updateCustomDiagram(diagramID: UUID, diagram: CustomDiagram) {
        // Check project-owned diagrams first.
        for i in store.projects.indices {
            if let j = store.projects[i].customDiagrams.firstIndex(where: { $0.id == diagramID }) {
                store.projects[i].customDiagrams[j] = diagram
                store.projects[i].customDiagrams[j].lastModified = Date()
                persistChanges()
                return
            }
        }
        // Check global diagrams.
        if let idx = store.globalCustomDiagrams.firstIndex(where: { $0.id == diagramID }) {
            store.globalCustomDiagrams[idx] = diagram
            store.globalCustomDiagrams[idx].lastModified = Date()
            persistChanges()
        }
    }
    
    func removeCustomDiagram(_ diagramID: UUID) {
        for i in store.projects.indices {
            store.projects[i].customDiagrams.removeAll { $0.id == diagramID }
        }
        store.globalCustomDiagrams.removeAll { $0.id == diagramID }
        persistChanges()
    }
    
    func customDiagram(for diagramID: UUID) -> CustomDiagram? {
        for p in store.projects {
            if let d = p.customDiagrams.first(where: { $0.id == diagramID }) { return d }
        }
        return store.globalCustomDiagrams.first(where: { $0.id == diagramID })
    }
    
    /// Convert a stored diagram to a custom diagram (copy nodes/edges as user-editable).
    ///
    /// - Parameters:
    ///   - storedDiagramID: The stored diagram to convert.
    ///   - livePositions: The positions currently shown on screen (from `ClassDiagramViewModel.nodePositions`).
    ///   - liveScale: Current canvas scale.
    ///   - liveOffset: Current canvas offset.
    func saveAsCustomDiagram(
        storedDiagramID: UUID,
        livePositions: [String: CGPoint] = [:],
        liveScale: CGFloat? = nil,
        liveOffset: CGPoint? = nil
    ) {
        guard let stored = storedDiagram(for: storedDiagramID),
              let pIdx = store.projects.firstIndex(where: { $0.storedDiagrams.contains(where: { $0.id == storedDiagramID }) }),
              let codebase = codebase(for: stored.codebaseID),
              let artifact = codebase.artifact else { return }
        
        var resolved = artifact.resolvingExtensions()
        if stored.configuration.hideGeneratedDartTypes && artifact.metadata.sourceLanguage == .dart {
            resolved = resolved.filteringGeneratedDartTypes()
        }
        var customNodes: [CustomDiagramNode] = []
        var customEdges: [CustomDiagramEdge] = []
        var nameToUUID: [String: UUID] = [:]
        
        for type in resolved.types {
            let nodeID = UUID()
            nameToUUID[type.name] = nodeID
            // Prefer live position over persisted position.
            let livePos = livePositions[type.name]
            let storedPos = stored.nodePositions[type.name]
            let x = livePos?.x ?? storedPos.map { CGFloat($0.x) } ?? 0
            let y = livePos?.y ?? storedPos.map { CGFloat($0.y) } ?? 0
            let customNode = CustomDiagramNode(
                id: nodeID,
                name: type.name,
                content: .type(TypeNodeContent(
                    typeKind: type.kind,
                    properties: type.members.filter { $0.kind == .property || $0.kind == .subscript }.map {
                        CustomMember(name: $0.name, type: $0.type?.name ?? "", accessLevel: $0.accessLevel ?? .internal, isStatic: $0.modifiers.contains(.static), isAbstract: $0.modifiers.contains(.abstract))
                    },
                    methods: type.members.filter { $0.kind == .method || $0.kind == .initializer || $0.kind == .deinitializer }.map {
                        CustomMember(name: $0.name, type: $0.type?.name ?? "", accessLevel: $0.accessLevel ?? .internal, isStatic: $0.modifiers.contains(.static), isAbstract: $0.modifiers.contains(.abstract))
                    },
                    enumCases: type.enumCases.map { CustomEnumCase(name: $0.name) },
                    genericParameters: type.genericParameters.map(\.name)
                )),
                positionX: Double(x),
                positionY: Double(y)
            )
            customNodes.append(customNode)
        }
        
        let typeNames = Set(resolved.types.map(\.name))
        for rel in resolved.relationships where typeNames.contains(rel.source) && typeNames.contains(rel.target) && rel.source != rel.target {
            if let srcID = nameToUUID[rel.source], let tgtID = nameToUUID[rel.target] {
                customEdges.append(CustomDiagramEdge(sourceNodeID: srcID, targetNodeID: tgtID, kind: rel.kind))
            }
        }

        let scale = liveScale.map(Double.init) ?? stored.canvasScale
        let offsetX = liveOffset.map { Double($0.x) } ?? stored.canvasOffsetX
        let offsetY = liveOffset.map { Double($0.y) } ?? stored.canvasOffsetY

        let custom = CustomDiagram(
            name: stored.name + " (Custom)",
            diagramType: stored.type,
            ownerProjectID: store.projects[pIdx].id,
            nodes: customNodes,
            edges: customEdges,
            canvasScale: scale,
            canvasOffsetX: offsetX,
            canvasOffsetY: offsetY
        )
        store.projects[pIdx].customDiagrams.append(custom)
        persistChanges()
        selection = .customDiagram(custom.id)
    }
    
    // MARK: - DOT Export
    
    func generateDOT(for codebaseID: UUID) -> String {
        guard let codebase = codebase(for: codebaseID) else { return "digraph UML { }" }
        let url = URL(fileURLWithPath: codebase.directoryPath).standardizedFileURL

        if var artifact = codebase.artifact {
            if artifact.metadata.sourceLanguage == .dart {
                artifact = artifact.filteringGeneratedDartTypes()
            }
            return DOTGenerator().generate(from: artifact)
        }

        // If no cached artifact, attempt an on-the-fly analysis.
        if var artifact = try? AnalysisService.shared.analyzeProject(at: url, allowedLanguages: []) {
            if artifact.metadata.sourceLanguage == .dart {
                artifact = artifact.filteringGeneratedDartTypes()
            }
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
    
    // MARK: - Helpers
    
    func projectID(for codebaseID: UUID) -> UUID? {
        for p in store.projects where p.codebases.contains(where: { $0.id == codebaseID }) { return p.id }
        return nil
    }
    
    func project(for projectID: UUID) -> Project? {
        store.projects.first(where: { $0.id == projectID })
    }
    
    func codebase(for codebaseID: UUID) -> Codebase? {
        for p in store.projects { if let c = p.codebases.first(where: { $0.id == codebaseID }) { return c } }
        return nil
    }
    
    func projectForDiagram(_ diagramID: UUID) -> Project? {
        store.projects.first(where: {
            $0.storedDiagrams.contains(where: { $0.id == diagramID }) ||
            $0.customDiagrams.contains(where: { $0.id == diagramID })
        })
    }
    
    /// All custom diagrams across all projects and global.
    var allCustomDiagrams: [CustomDiagram] {
        store.projects.flatMap(\.customDiagrams) + store.globalCustomDiagrams
    }
    
    func storedDiagrams(for codebaseID: UUID) -> [StoredDiagram] {
        store.projects.flatMap(\.storedDiagrams).filter { $0.codebaseID == codebaseID }
    }
}

