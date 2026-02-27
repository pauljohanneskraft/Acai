import UMLCore

/// Renders `Relationship` values as DOT edge definitions.
struct DOTEdgeRenderer {
    let options: DiagramOptions

    func render(relationships: [Relationship]) -> String {
        relationships
            .filter { options.includedRelationshipKinds.contains($0.kind) }
            .map { render($0) }
            .joined()
    }

    private func render(_ rel: Relationship) -> String {
        let source = rel.source.dotNodeID
        let target = rel.target.dotNodeID
        let attrs = edgeAttributes(for: rel.kind)
        var labels = ""
        if let label = rel.label {
            labels += " label=\"\(label.dotEscaped)\""
        }
        if let sourceLabel = rel.sourceLabel {
            labels += " taillabel=\"\(sourceLabel.dotEscaped)\""
        }
        if let targetLabel = rel.targetLabel {
            labels += " headlabel=\"\(targetLabel.dotEscaped)\""
        }
        return "  \(source) -> \(target) [\(attrs)\(labels)];\n"
    }

    private func edgeAttributes(for kind: Relationship.Kind) -> String {
        let color = options.theme.edgeColor
        switch kind {
        case .inheritance:
            return "arrowhead=empty style=solid color=\"\(color)\""
        case .conformance:
            return "arrowhead=empty style=dashed color=\"\(color)\""
        case .composition:
            return "dir=back arrowtail=diamond color=\"\(color)\""
        case .aggregation:
            return "dir=back arrowtail=odiamond color=\"\(color)\""
        case .association:
            return "arrowhead=vee style=solid color=\"\(color)\""
        case .dependency:
            return "arrowhead=vee style=dashed color=\"\(color)\""
        case .extension:
            return "arrowhead=empty style=dotted color=\"\(color)\""
        case .nesting:
            return "arrowhead=dot style=solid color=\"\(color)\""
        }
    }
}
