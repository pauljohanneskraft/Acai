import Foundation
import AcaiCore
import AcaiDiagram
import AcaiDiff
import AcaiRender

/// What VoiceOver says about one canvas node or edge: its name, then the facts a sighted user reads
/// off its shape — kind, counts, change status.
struct DiagramElementDescription {
    /// Content, not chrome: a type, state or module name as the parser produced it.
    let label: String
    let details: [LocalizedStringResource]

    var value: String {
        details.map { String(localized: $0) }.formatted(.list(type: .and, width: .narrow))
    }

    /// Label and value as one phrase, for an element whose label is already taken.
    var summary: String {
        ([label] + details.map { String(localized: $0) }).formatted(.list(type: .and, width: .narrow))
    }
}

extension DiagramElementDescription {
    init(typeNode node: GeneratedDiagramNode, delta: DeltaStatus?) {
        let details = TypeMemberCounts(
            kind: node.kind,
            properties: node.properties.removingDuplicates(by: \.id).count,
            methods: node.methods.removingDuplicates(by: \.id).count,
            enumCases: node.enumCases.removingDuplicates(by: \.id).count
        ).details
        self.init(label: node.name, details: details + delta.changeDetails)
    }

    init(callGraphNode node: CallGraph.Node, in graph: CallGraph, delta: DeltaStatus?) {
        let callsOut = graph.edges.filter { $0.from == node.id }.count
        let calledBy = graph.edges.filter { $0.to == node.id }.count
        var details: [LocalizedStringResource] = [
            node.isFreeFunction ? .app("DiagramElementDescription.Function") : .app("DiagramElementDescription.Method"),
            .app("DiagramElementDescription.CallsOut \(callsOut)"),
            .app("DiagramElementDescription.CalledBy \(calledBy)")
        ]
        if !node.inScope { details.append(.app("DiagramElementDescription.OutsideScope")) }
        self.init(label: node.label, details: details + delta.changeDetails)
    }

    init(packageNode node: PackageDiagram.Node, delta: DeltaStatus?) {
        let instability = node.instability.formatted(.percent.precision(.fractionLength(0)))
        let details: [LocalizedStringResource] = [
            .app("DiagramElementDescription.Module"),
            .app("DiagramElementDescription.Types \(node.typeCount)"),
            .app("DiagramElementDescription.UsedBy \(node.afferentCoupling)"),
            .app("DiagramElementDescription.Uses \(node.efferentCoupling)"),
            .app("DiagramElementDescription.Instability \(instability)")
        ]
        self.init(label: node.name, details: details + delta.changeDetails)
    }

    init(state: StateDiagram.State, delta: DeltaStatus?) {
        self.init(label: state.name, details: [state.kind.title] + delta.changeDetails)
    }

    init(participantNamed name: String, kind: SequenceDiagram.Participant.Kind, delta: DeltaStatus?) {
        self.init(label: name, details: [kind.title] + delta.changeDetails)
    }

    init(freeformNode node: FreeformDiagram.Node) {
        let details: [LocalizedStringResource] = if case .type(let type) = node.content {
            TypeMemberCounts(
                kind: type.typeKind, properties: type.properties.count, methods: type.methods.count,
                enumCases: type.enumCases.count
            ).details
        } else {
            [node.content.title]
        }
        let label = if case .note(let text) = node.content, !text.isEmpty {
            [node.name, text].formatted(.list(type: .and, width: .narrow))
        } else {
            node.name
        }
        self.init(label: label, details: details)
    }

    init(freeformEdge edge: FreeformDiagram.Edge, sourceName: String, targetName: String) {
        var details: [LocalizedStringResource] = [
            edge.transition != nil ? .app("DiagramElementDescription.Transition") : edge.kind.title
        ]
        if let label = edge.transition?.label ?? edge.label, !label.isEmpty {
            details.append(.app("DiagramElementDescription.EdgeLabel \(label)"))
        }
        self.init(edgeFrom: sourceName, to: targetName, details: details, delta: nil)
    }

    /// An edge reads as "From A to B", then what kind of connection it is.
    init(edgeFrom source: String, to target: String, details: [LocalizedStringResource], delta: DeltaStatus?) {
        self.init(
            label: String(localized: .app("DiagramElementDescription.Edge \(source) \(target)")),
            details: details + delta.changeDetails)
    }

    init(classEdge edge: GeneratedDiagramEdge, sourceName: String, targetName: String, delta: DeltaStatus?) {
        var details = [edge.kind.title]
        if let multiplicity = edge.sourceLabel {
            details.append(.app("DiagramElementDescription.SourceMultiplicity \(multiplicity)"))
        }
        if let multiplicity = edge.targetLabel {
            details.append(.app("DiagramElementDescription.TargetMultiplicity \(multiplicity)"))
        }
        self.init(edgeFrom: sourceName, to: targetName, details: details, delta: delta)
    }

    /// `weight` counts distinct call sites (call graph) or cross-module references (package diagram).
    init(dependencyFrom source: String, to target: String, callSites weight: Int, delta: DeltaStatus?) {
        self.init(
            edgeFrom: source, to: target,
            details: [.app("DiagramElementDescription.Call"), .app("DiagramElementDescription.CallSites \(weight)")],
            delta: delta)
    }

    init(dependencyFrom source: String, to target: String, references weight: Int, delta: DeltaStatus?) {
        self.init(
            edgeFrom: source, to: target,
            details: [
                Relationship.Kind.dependency.title, .app("DiagramElementDescription.References \(weight)")
            ],
            delta: delta)
    }

    func edgeAccessibility(identifier: String? = nil) -> EdgeAccessibility {
        EdgeAccessibility(label: label, value: value, identifier: identifier)
    }
}

private struct TypeMemberCounts {
    let kind: TypeKind
    let properties: Int
    let methods: Int
    let enumCases: Int

    var details: [LocalizedStringResource] {
        var details = [kind.title]
        if properties > 0 { details.append(.app("DiagramElementDescription.Properties \(properties)")) }
        if methods > 0 { details.append(.app("DiagramElementDescription.Functions \(methods)")) }
        if enumCases > 0 { details.append(.app("DiagramElementDescription.EnumCases \(enumCases)")) }
        return details
    }
}

extension DeltaStatus? {
    fileprivate var changeDetails: [LocalizedStringResource] {
        switch self {
        case .added:
            [.app("DiagramElementDescription.Added")]
        case .removed:
            [.app("DiagramElementDescription.Removed")]
        case .changed:
            [.app("DiagramElementDescription.Changed")]
        case .unchanged, nil:
            []
        }
    }
}
