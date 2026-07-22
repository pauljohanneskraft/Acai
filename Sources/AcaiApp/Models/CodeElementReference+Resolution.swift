import AcaiCore
import AcaiDiagram
import AcaiRender

extension CodeElementReference {
    /// Every diagram type that can meaningfully show this element (the element-kind table in
    /// `USABILITY_IMPROVEMENTS.md` Part 2), each resolved to an already-open diagram containing it
    /// when one exists among `existingDiagrams` (expected to already be scoped to one codebase),
    /// else a pre-scoped `GeneratedDiagram.Content` ready to create one.
    func resolutions(in artifact: CodeArtifact, existingDiagrams: [GeneratedDiagram]) -> [CodeElementResolution] {
        switch self {
        case .type(let id):
            return typeResolutions(id: id, artifact: artifact, existingDiagrams: existingDiagrams)
        case .method(let typeName, let methodName):
            return methodResolutions(typeName: typeName, methodName: methodName, existingDiagrams: existingDiagrams)
        case .module(let name):
            return moduleResolutions(name: name, existingDiagrams: existingDiagrams)
        case .relationship(let source, _, _):
            return relationshipResolutions(source: source, existingDiagrams: existingDiagrams)
        }
    }

    // MARK: - Type

    private func typeResolutions(
        id: String, artifact: CodeArtifact, existingDiagrams: [GeneratedDiagram]
    ) -> [CodeElementResolution] {
        guard let type = artifact.flattened().first(where: { $0.id == id }) else { return [] }
        var resolutions: [CodeElementResolution] = [
            .init(diagramType: .classDiagram, target: classDiagramTarget(focusedOn: id, in: existingDiagrams)),
            .init(diagramType: .callGraph, target: callGraphTarget(scope: .type(type.name), in: existingDiagrams)),
            .init(diagramType: .packageDiagram, target: packageDiagramTarget(in: existingDiagrams))
        ]
        if let property = artifact.enumTypedProperty(of: type) {
            resolutions.append(.init(
                diagramType: .stateDiagram,
                target: stateDiagramTarget(typeName: type.name, variableName: property.name, in: existingDiagrams)
            ))
        }
        return resolutions
    }

    // MARK: - Method

    private func methodResolutions(
        typeName: String?, methodName: String, existingDiagrams: [GeneratedDiagram]
    ) -> [CodeElementResolution] {
        let entryTypeName = typeName ?? ""
        let sequenceTarget: CodeElementResolution.Target
        if let existing = existingDiagrams.first(where: {
            $0.sequenceConfiguration?.entryTypeName == entryTypeName
                && $0.sequenceConfiguration?.entryMethodName == methodName
        }) {
            sequenceTarget = .existing(existing.id)
        } else {
            sequenceTarget = .create(.sequenceDiagram(
                .init(entryTypeName: entryTypeName, entryMethodName: methodName)
            ))
        }
        let scope: CallGraphScope = typeName.map(CallGraphScope.type) ?? .wholeCodebase
        return [
            .init(diagramType: .sequenceDiagram, target: sequenceTarget),
            .init(diagramType: .callGraph, target: callGraphTarget(scope: scope, in: existingDiagrams))
        ]
    }

    // MARK: - Module

    private func moduleResolutions(name: String, existingDiagrams: [GeneratedDiagram]) -> [CodeElementResolution] {
        // Class Diagram's module filter doesn't exist yet (Part 12's Selector-based filtering) —
        // only Package Diagram is actually buildable today, so that's the only thing offered;
        // offering a "filtered" Class Diagram that can't actually filter would be a broken promise.
        [.init(diagramType: .packageDiagram, target: packageDiagramTarget(in: existingDiagrams))]
    }

    // MARK: - Relationship

    private func relationshipResolutions(
        source: String, existingDiagrams: [GeneratedDiagram]
    ) -> [CodeElementResolution] {
        // Cycle Diagram (Part 11 / B58) doesn't exist yet, so Class Diagram is the only offer —
        // focused on the source with a two-way, one-hop neighborhood, which for a real edge
        // includes the target too (and, for a cycle's first member, its immediate neighbors).
        [.init(diagramType: .classDiagram, target: classDiagramTarget(focusedOn: source, in: existingDiagrams))]
    }

    // MARK: - Shared target builders

    private func classDiagramTarget(
        focusedOn typeId: String, in existingDiagrams: [GeneratedDiagram]
    ) -> CodeElementResolution.Target {
        if let exact = existingDiagrams.first(where: { $0.classConfiguration?.focus?.rootTypeName == typeId }) {
            return .existing(exact.id)
        }
        if let unfocused = existingDiagrams.first(where: {
            $0.type == .classDiagram && $0.classConfiguration?.focus == nil
        }) {
            return .existing(unfocused.id)
        }
        var configuration = ClassDiagramConfiguration()
        configuration.focus = .init(rootTypeName: typeId, maxDepth: 1, direction: .both)
        return .create(.classDiagram(configuration))
    }

    private func callGraphTarget(
        scope: CallGraphScope, in existingDiagrams: [GeneratedDiagram]
    ) -> CodeElementResolution.Target {
        if let exact = existingDiagrams.first(where: { $0.callGraphScope == scope }) {
            return .existing(exact.id)
        }
        if case .type = scope,
           let wholeCodebase = existingDiagrams.first(where: { $0.callGraphScope == .wholeCodebase }) {
            return .existing(wholeCodebase.id)
        }
        return .create(.callGraph(scope))
    }

    private func packageDiagramTarget(in existingDiagrams: [GeneratedDiagram]) -> CodeElementResolution.Target {
        if let existing = existingDiagrams.first(where: { $0.type == .packageDiagram }) {
            return .existing(existing.id)
        }
        return .create(.packageDiagram)
    }

    private func stateDiagramTarget(
        typeName: String, variableName: String, in existingDiagrams: [GeneratedDiagram]
    ) -> CodeElementResolution.Target {
        if let existing = existingDiagrams.first(where: {
            $0.stateConfiguration?.typeName == typeName && $0.stateConfiguration?.variableName == variableName
        }) {
            return .existing(existing.id)
        }
        return .create(.stateDiagram(.init(typeName: typeName, variableName: variableName)))
    }
}

extension CodeArtifact {
    /// The first property of `type` whose declared type is a known `enum` elsewhere in this
    /// artifact — a State Diagram's traceable-variable requirement, checked structurally (by
    /// simple-name match) rather than requiring full identity resolution, since this only needs to
    /// decide whether *offering* a State Diagram resolution is worthwhile, not to build one.
    fileprivate func enumTypedProperty(of type: TypeDeclaration) -> Member? {
        let enumNames = Set(flattened().filter { $0.kind == .enum }.map(\.name))
        return type.members.first {
            $0.kind == .property && $0.type.map { enumNames.contains($0.name) } == true
        }
    }
}
