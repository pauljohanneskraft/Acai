import UMLCore

/// Renders a `DeploymentDiagram` to Graphviz DOT format.
///
/// Each `Node` becomes a `subgraph` cluster (nested clusters for child nodes).
/// `Artifact` values are rendered as record-shaped boxes inside their host cluster.
/// `CommunicationPath` values are edges between clusters, drawn using DOT's
/// `compound=true` / `lhead` / `ltail` attributes so that arrow endpoints appear
/// on the cluster border rather than on an internal node.
public struct DeploymentDiagramDOTRenderer: Sendable {
    public let theme: DiagramTheme
    public let fontName: String
    public let fontSize: Int

    public init(
        theme: DiagramTheme = .default,
        fontName: String = "Helvetica",
        fontSize: Int = 12
    ) {
        self.theme = theme
        self.fontName = fontName
        self.fontSize = fontSize
    }

    // MARK: - Public API

    public func render(_ diagram: DeploymentDiagram) -> String {
        var out = "digraph {\n"
        if let title = diagram.title {
            out += "  label=\"\(title.dotEscaped)\";\n"
            out += "  labelloc=t;\n"
        }
        out += graphAttributes()

        // Render each top-level node as a cluster; collect anchor-node ids
        var anchorMap: [String: String] = [:]  // node.id → anchor node DOT id
        var clusterIndex = 0
        for node in diagram.nodes {
            let (dot, anchors, nextIndex) = renderNode(node, clusterIndex: clusterIndex, indent: "  ")
            out += dot
            anchorMap.merge(anchors) { _, new in new }
            clusterIndex = nextIndex
        }

        // Communication paths – connect via anchors using lhead/ltail
        for path in diagram.communicationPaths {
            guard
                let fromAnchor = anchorMap[path.from],
                let toAnchor   = anchorMap[path.to]
            else { continue }

            let color = theme.edgeColor
            var attrs = "color=\"\(color)\" dir=both arrowhead=open arrowtail=open"
            attrs += " lhead=cluster_\(path.to) ltail=cluster_\(path.from)"
            var label = ""
            if let lbl = path.label { label += lbl }
            if let proto = path.protocolName {
                label += label.isEmpty ? proto : " (\(proto))"
            }
            if !label.isEmpty { attrs += " label=\"\(label.dotEscaped)\"" }
            out += "  \(fromAnchor) -> \(toAnchor) [\(attrs)];\n"
        }

        out += "}\n"
        return out
    }

    // MARK: - Node rendering

    /// Returns (DOT text, anchor map for this node subtree, next cluster index).
    private func renderNode(
        _ node: DeploymentDiagram.Node,
        clusterIndex: Int,
        indent: String
    ) -> (String, [String: String], Int) {
        var out = "\(indent)subgraph cluster_\(node.id) {\n"
        out += "\(indent)  label=\"\(nodeLabel(node).dotEscaped)\";\n"
        out += "\(indent)  style=\(clusterStyle(node.kind));\n"
        out += "\(indent)  color=\"\(theme.nodeBorderColor)\";\n"
        out += "\(indent)  fontcolor=\"\(theme.fontColor)\";\n"

        // Invisible anchor node – used as a connection point for communication paths
        let anchorId = "\"\(node.id)_anchor\""
        out += "\(indent)  \(anchorId) [shape=none label=\"\" width=0 height=0];\n"

        var anchorMap: [String: String] = [node.id: anchorId]
        var nextIndex = clusterIndex + 1

        // Artifacts
        for artifact in node.artifacts {
            out += "\(indent)  \(renderArtifact(artifact, indent: indent + "  "))\n"
        }

        // Child nodes (nested clusters)
        for child in node.children {
            let (childDot, childAnchors, ni) = renderNode(child, clusterIndex: nextIndex, indent: indent + "  ")
            out += childDot
            anchorMap.merge(childAnchors) { _, new in new }
            nextIndex = ni
        }

        out += "\(indent)}\n"
        return (out, anchorMap, nextIndex)
    }

    private func renderArtifact(_ artifact: DeploymentDiagram.Artifact, indent: String) -> String {
        let nodeId = artifact.id.dotNodeID
        let stereotype = artifact.kind.rawValue
        let fill = theme.nodeFillColor
        let border = theme.nodeBorderColor
        let font = theme.fontColor
        let label = "<TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\">" +
                    "<TR><TD><FONT POINT-SIZE=\"\(fontSize - 2)\" COLOR=\"\(font)\">" +
                    "&lt;&lt;\(stereotype)&gt;&gt;</FONT></TD></TR>" +
                    "<TR><TD><FONT COLOR=\"\(font)\">\(artifact.name.dotHTMLEscaped)</FONT></TD></TR>" +
                    "</TABLE>"
        return "\(nodeId) [label=<\(label)> shape=box style=filled fillcolor=\"\(fill)\" color=\"\(border)\"];"
    }

    // MARK: - Helpers

    private func nodeLabel(_ node: DeploymentDiagram.Node) -> String {
        let stereotype: String
        switch node.kind {
        case .device:               stereotype = "device"
        case .executionEnvironment: stereotype = "executionEnvironment"
        case .server:               stereotype = "server"
        }
        return "<<\(stereotype)>>\n\(node.name)"
    }

    private func clusterStyle(_ kind: DeploymentDiagram.Node.Kind) -> String {
        switch kind {
        case .device:               return "\"filled,rounded\""
        case .executionEnvironment: return "dashed"
        case .server:               return "rounded"
        }
    }

    // MARK: - Graph attributes

    private func graphAttributes() -> String {
        """
          rankdir=TB;
          bgcolor="\(theme.backgroundColor)";
          compound=true;
          fontname="\(fontName)";
          fontsize=\(fontSize);
          node [fontname="\(fontName)" fontsize=\(fontSize)];
          edge [fontname="\(fontName)" fontsize=\(fontSize - 2)];

        """
    }
}
