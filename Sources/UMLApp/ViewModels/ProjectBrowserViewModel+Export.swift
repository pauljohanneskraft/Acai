import Foundation
import SwiftUI
import UMLLibrary
import UMLCore
import UMLDiagram

// MARK: - DOT Export & Custom Diagram Conversion

extension ProjectBrowserViewModel {

    // MARK: DOT Export

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

    // MARK: Save as Custom Diagram

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

        let (customNodes, nameToUUID) = buildCustomNodes(
            from: resolved, stored: stored, livePositions: livePositions
        )
        let customEdges = buildCustomEdges(from: resolved, nameToUUID: nameToUUID)

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

    private func buildCustomNodes(
        from resolved: CodeArtifact,
        stored: StoredDiagram,
        livePositions: [String: CGPoint]
    ) -> ([CustomDiagramNode], [String: UUID]) {
        var nodes: [CustomDiagramNode] = []
        var nameToUUID: [String: UUID] = [:]

        for type in resolved.types {
            let nodeID = UUID()
            nameToUUID[type.name] = nodeID
            let livePos = livePositions[type.name]
            let storedPos = stored.nodePositions[type.name]
            let x = livePos?.x ?? storedPos.map { CGFloat($0.x) } ?? 0
            let y = livePos?.y ?? storedPos.map { CGFloat($0.y) } ?? 0
            nodes.append(CustomDiagramNode(
                id: nodeID,
                name: type.name,
                content: .type(TypeNodeContent(
                    typeKind: type.kind,
                    properties: type.members
                        .filter { $0.kind == .property || $0.kind == .subscript }
                        .map { customMember(from: $0) },
                    methods: type.members
                        .filter { $0.kind == .method || $0.kind == .initializer || $0.kind == .deinitializer }
                        .map { customMember(from: $0) },
                    enumCases: type.enumCases.map { CustomEnumCase(name: $0.name) },
                    genericParameters: type.genericParameters.map(\.name)
                )),
                positionX: Double(x),
                positionY: Double(y)
            ))
        }
        return (nodes, nameToUUID)
    }

    private func customMember(from member: Member) -> CustomMember {
        CustomMember(
            name: member.name,
            type: member.type?.name ?? "",
            accessLevel: member.accessLevel ?? .internal,
            isStatic: member.modifiers.contains(.static),
            isAbstract: member.modifiers.contains(.abstract)
        )
    }

    private func buildCustomEdges(
        from resolved: CodeArtifact,
        nameToUUID: [String: UUID]
    ) -> [CustomDiagramEdge] {
        let typeNames = Set(resolved.types.map(\.name))
        return resolved.relationships.compactMap { rel in
            guard typeNames.contains(rel.source),
                  typeNames.contains(rel.target),
                  rel.source != rel.target,
                  let srcID = nameToUUID[rel.source],
                  let tgtID = nameToUUID[rel.target] else { return nil }
            return CustomDiagramEdge(sourceNodeID: srcID, targetNodeID: tgtID, kind: rel.kind)
        }
    }
}
