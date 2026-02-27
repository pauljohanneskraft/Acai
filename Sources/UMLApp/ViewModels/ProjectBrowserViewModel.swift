import Foundation
import SwiftUI
import UMLLibrary
import UMLCore
import UMLDiagram

@MainActor
final class ProjectBrowserViewModel: ObservableObject {
    @Published var store: ProjectStore
    @Published var selection: Selection?

    enum Selection: Hashable {
        case project(UUID)
        case codebase(UUID)
        case diagram(UUID)
        case customDiagram(UUID)
    }

    init(store: ProjectStore = ProjectStore()) {
        self.store = store
    }

    private func persistChanges() {
        store.save()
        objectWillChange.send()
    }

    private func persistProject(_ projectID: UUID) {
        if let project = store.projects.first(where: { $0.id == projectID }) {
            store.saveProject(project)
        }
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
        guard let project = store.projects.first(where: { $0.id == projectID }) else { return }
        // Clean up diagram files
        for did in project.storedDiagramIDs { store.deleteStoredDiagramFile(did) }
        for did in project.customDiagramIDs { store.deleteCustomDiagramFile(did) }
        store.deleteProjectFile(projectID)
        store.projects.removeAll { $0.id == projectID }
        persistChanges()
    }

    // MARK: - Codebase CRUD

    func addCodebase(to projectID: UUID, name: String, directoryURL: URL) {
        guard let idx = store.projects.firstIndex(where: { $0.id == projectID }) else { return }
        let codebase = Codebase(name: name, directoryPath: directoryURL.path)
        store.projects[idx].codebases.append(codebase)
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
            // Remove stored diagrams linked to this codebase.
            let toRemove = store.projects[i].storedDiagramIDs.filter { did in
                store.storedDiagrams[did]?.codebaseID == codebaseID
            }
            for did in toRemove {
                store.projects[i].storedDiagramIDs.removeAll { $0 == did }
                store.deleteStoredDiagramFile(did)
            }
        }
        store.deleteArtifactFile(for: codebaseID)
        persistChanges()
    }

    func reindex(codebaseID: UUID) async {
        guard let pIndex = store.projects.firstIndex(where: { $0.id == projectID(for: codebaseID) }),
              let cIndex = store.projects[pIndex].codebases.firstIndex(where: { $0.id == codebaseID }) else { return }
        let url = URL(fileURLWithPath: store.projects[pIndex].codebases[cIndex].directoryPath).standardizedFileURL

        do {
            let artifact = try await Task.detached(priority: .userInitiated) {
                try AnalysisService.shared.analyzeProject(at: url, allowedLanguages: [])
            }.value
            store.projects[pIndex].codebases[cIndex].hasArtifact = true
            store.projects[pIndex].codebases[cIndex].lastIndexed = Date()
            store.saveArtifact(artifact, for: codebaseID)
            persistProject(store.projects[pIndex].id)
        } catch {
            print("Reindex failed: \(error)")
        }
    }

    // MARK: - Stored Diagram CRUD

    func addStoredDiagram(
        to projectID: UUID,
        codebaseID: UUID,
        name: String,
        type: DiagramType,
        configuration: DiagramConfiguration
    ) -> UUID? {
        guard let idx = store.projects.firstIndex(where: { $0.id == projectID }) else { return nil }
        let diagram = StoredDiagram(name: name, type: type, codebaseID: codebaseID, configuration: configuration)
        store.projects[idx].storedDiagramIDs.append(diagram.id)
        store.saveStoredDiagram(diagram)
        persistChanges()
        return diagram.id
    }

    func updateStoredDiagramPositions(
        diagramID: UUID,
        positions: [String: CGPoint],
        sizes: [String: CGSize] = [:],
        scale: CGFloat,
        offset: CGPoint
    ) {
        guard var diagram = store.storedDiagrams[diagramID] else { return }
        diagram.nodePositions = positions.mapValues { StoredNodePosition(point: $0) }
        if !sizes.isEmpty {
            diagram.nodeSizes = sizes.mapValues { StoredNodeSize(size: $0) }
        }
        diagram.canvasScale = Double(scale)
        diagram.canvasOffsetX = Double(offset.x)
        diagram.canvasOffsetY = Double(offset.y)
        diagram.lastModified = Date()
        store.saveStoredDiagram(diagram)
        objectWillChange.send()
    }

    func updateStoredDiagramConfiguration(diagramID: UUID, configuration: DiagramConfiguration) {
        guard var diagram = store.storedDiagrams[diagramID] else { return }
        diagram.configuration = configuration
        diagram.lastModified = Date()
        store.saveStoredDiagram(diagram)
        objectWillChange.send()
    }

    func renameStoredDiagram(_ diagramID: UUID, name: String) {
        guard var diagram = store.storedDiagrams[diagramID] else { return }
        diagram.name = name
        diagram.lastModified = Date()
        store.saveStoredDiagram(diagram)
        objectWillChange.send()
    }

    func removeStoredDiagram(_ diagramID: UUID) {
        for i in store.projects.indices {
            store.projects[i].storedDiagramIDs.removeAll { $0 == diagramID }
        }
        store.deleteStoredDiagramFile(diagramID)
        persistChanges()
    }

    func storedDiagram(for diagramID: UUID) -> StoredDiagram? {
        store.storedDiagrams[diagramID]
    }

    // MARK: - Custom Diagram CRUD

    func addCustomDiagram(to projectID: UUID, name: String, type: DiagramType) -> UUID? {
        guard let idx = store.projects.firstIndex(where: { $0.id == projectID }) else { return nil }
        var diagram = CustomDiagram(name: name, diagramType: type)
        diagram.ownerProjectID = projectID
        store.projects[idx].customDiagramIDs.append(diagram.id)
        store.saveCustomDiagram(diagram)
        persistChanges()
        return diagram.id
    }

    func updateCustomDiagram(diagramID: UUID, diagram: CustomDiagram) {
        var updated = diagram
        updated.lastModified = Date()
        store.saveCustomDiagram(updated)
        objectWillChange.send()
    }

    func renameCustomDiagram(_ diagramID: UUID, name: String) {
        guard var diagram = store.customDiagrams[diagramID] else { return }
        diagram.name = name
        diagram.lastModified = Date()
        store.saveCustomDiagram(diagram)
        objectWillChange.send()
    }

    func removeCustomDiagram(_ diagramID: UUID) {
        for i in store.projects.indices {
            store.projects[i].customDiagramIDs.removeAll { $0 == diagramID }
        }
        store.deleteCustomDiagramFile(diagramID)
        persistChanges()
    }

    func customDiagram(for diagramID: UUID) -> CustomDiagram? {
        store.customDiagrams[diagramID]
    }

    /// Convert a stored diagram to a custom diagram.
    func saveAsCustomDiagram(
        storedDiagramID: UUID,
        livePositions: [String: CGPoint] = [:],
        liveScale: CGFloat? = nil,
        liveOffset: CGPoint? = nil
    ) {
        guard let stored = storedDiagram(for: storedDiagramID),
              let pIdx = store.projects.firstIndex(where: { $0.storedDiagramIDs.contains(storedDiagramID) }),
              let codebase = codebase(for: stored.codebaseID),
              let artifact = artifact(for: stored.codebaseID) else { return }

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
            let livePos = livePositions[type.name]
            let storedPos = stored.nodePositions[type.name]
            let x = livePos?.x ?? storedPos.map { CGFloat($0.x) } ?? 0
            let y = livePos?.y ?? storedPos.map { CGFloat($0.y) } ?? 0
            let customNode = CustomDiagramNode(
                id: nodeID,
                name: type.name,
                content: .type(TypeNodeContent(
                    typeKind: type.kind,
                    properties: type.members
                        .filter { $0.kind == .property || $0.kind == .subscript }
                        .map {
                            CustomMember(
                                name: $0.name,
                                type: $0.type?.name ?? "",
                                accessLevel: $0.accessLevel ?? .internal,
                                isStatic: $0.modifiers.contains(.static),
                                isAbstract: $0.modifiers.contains(.abstract)
                            )
                        },
                    methods: type.members
                        .filter { $0.kind == .method || $0.kind == .initializer || $0.kind == .deinitializer }
                        .map {
                            CustomMember(
                                name: $0.name,
                                type: $0.type?.name ?? "",
                                accessLevel: $0.accessLevel ?? .internal,
                                isStatic: $0.modifiers.contains(.static),
                                isAbstract: $0.modifiers.contains(.abstract)
                            )
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
        for rel in resolved.relationships
            where typeNames.contains(rel.source)
                && typeNames.contains(rel.target)
                && rel.source != rel.target {
            if let srcID = nameToUUID[rel.source], let tgtID = nameToUUID[rel.target] {
                customEdges.append(CustomDiagramEdge(sourceNodeID: srcID, targetNodeID: tgtID, kind: rel.kind))
            }
        }

        let scale = liveScale.map(Double.init) ?? stored.canvasScale
        let offsetX = liveOffset.map { Double($0.x) } ?? stored.canvasOffsetX
        let offsetY = liveOffset.map { Double($0.y) } ?? stored.canvasOffsetY

        var custom = CustomDiagram(
            name: stored.name + " (Custom)",
            diagramType: stored.type,
            ownerProjectID: store.projects[pIdx].id,
            nodes: customNodes,
            edges: customEdges,
            canvasScale: scale,
            canvasOffsetX: offsetX,
            canvasOffsetY: offsetY
        )
        store.projects[pIdx].customDiagramIDs.append(custom.id)
        store.saveCustomDiagram(custom)
        persistChanges()
        selection = .customDiagram(custom.id)
    }

    // MARK: - DOT Export

    func generateDOT(for codebaseID: UUID) -> String {
        guard let codebase = codebase(for: codebaseID) else { return "digraph UML { }" }
        let url = URL(fileURLWithPath: codebase.directoryPath).standardizedFileURL

        if var artifact = artifact(for: codebaseID) {
            if artifact.metadata.sourceLanguage == .dart {
                artifact = artifact.filteringGeneratedDartTypes()
            }
            return DOTGenerator().generate(from: artifact)
        }

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
            do {
                try dot.data(using: .utf8)?.write(to: url, options: .atomic)
            } catch {
                print("Export failed: \(error)")
            }
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

    func artifact(for codebaseID: UUID) -> CodeArtifact? {
        store.artifact(for: codebaseID)
    }

    func projectForDiagram(_ diagramID: UUID) -> Project? {
        store.projects.first(where: {
            $0.storedDiagramIDs.contains(diagramID) ||
            $0.customDiagramIDs.contains(diagramID)
        })
    }

    func storedDiagrams(for codebaseID: UUID) -> [StoredDiagram] {
        store.storedDiagrams.values.filter { $0.codebaseID == codebaseID }
    }

    /// All stored diagrams for a project.
    func storedDiagramsForProject(_ projectID: UUID) -> [StoredDiagram] {
        guard let project = store.projects.first(where: { $0.id == projectID }) else { return [] }
        return project.storedDiagramIDs.compactMap { store.storedDiagrams[$0] }
    }

    /// All custom diagrams for a project.
    func customDiagramsForProject(_ projectID: UUID) -> [CustomDiagram] {
        guard let project = store.projects.first(where: { $0.id == projectID }) else { return [] }
        return project.customDiagramIDs.compactMap { store.customDiagrams[$0] }
    }
}
