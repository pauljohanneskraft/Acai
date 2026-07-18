import AcaiCore

/// Renders `Relationship` values as DOT edge definitions.
struct DOTEdgeRenderer {
    let options: ClassDiagramOptions

    func render(relationships: [Relationship]) -> String {
        relationships
            .filter { options.includedRelationshipKinds.contains($0.kind) }
            .map { render($0) }
            .joined()
    }

    private func render(_ rel: Relationship) -> String {
        let source = rel.source.dotNodeID
        let target = rel.target.dotNodeID
        let attrs = edgeAttributes(for: rel)
        var labels = ""
        if let label = rel.label {
            labels += " label=\"\(label.dotEscaped)\""
        }
        if options.showMultiplicities {
            if let sourceLabel = rel.sourceLabel {
                labels += " taillabel=\"\(sourceLabel.dotEscaped)\""
            }
            if let targetLabel = rel.targetLabel {
                labels += " headlabel=\"\(targetLabel.dotEscaped)\""
            }
        }
        return "  \(source) -> \(target) [\(attrs)\(labels)];\n"
    }

    private func edgeAttributes(for rel: Relationship) -> String {
        // Edge colour is cosmetic; arrowheads/styles are semantic and always emitted. A per-edge
        // override (delta diagram) wins over the theme; when both are absent no colour is emitted,
        // so structural output is unchanged.
        let color = options.edgeColorOverride?(rel) ?? options.theme?.edgeColor
        let colorAttr = color.map { " color=\"\($0)\"" } ?? ""
        switch rel.kind {
        case .inheritance:
            return "arrowhead=empty style=solid" + colorAttr
        case .conformance:
            return "arrowhead=empty style=dashed" + colorAttr
        case .composition:
            return "dir=back arrowtail=diamond" + colorAttr
        case .aggregation:
            return "dir=back arrowtail=odiamond" + colorAttr
        case .association:
            return "arrowhead=vee style=solid" + colorAttr
        case .dependency:
            return "arrowhead=vee style=dashed" + colorAttr
        case .extension:
            return "arrowhead=empty style=dotted" + colorAttr
        case .nesting:
            return "arrowhead=dot style=solid" + colorAttr
        }
    }
}
