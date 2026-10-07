import Foundation

/// The Mermaid half of the coupling view: each module labelled with its full metric set
/// (`Ca`/`Ce`/`I`/`A`/`D`) and its named main-sequence zone, shaded by distance from the line, with
/// Stable-Dependencies-Principle breaches drawn as dotted links.
public struct ModuleCouplingMermaidRenderer: MermaidRenderer {
    public let theme: DiagramTheme?
    private let nodeColor: (@Sendable (String) -> String?)?
    private let edgeColor: (@Sendable (String, String) -> String?)?

    public init(
        theme: DiagramTheme? = nil,
        nodeColor: (@Sendable (String) -> String?)? = nil,
        edgeColor: (@Sendable (String, String) -> String?)? = nil
    ) {
        self.theme = theme
        self.nodeColor = nodeColor
        self.edgeColor = edgeColor
    }

    public func render(_ diagram: PackageDiagram) -> String {
        var lines: [String] = []
        if let title = diagram.title {
            lines.append("---")
            lines.append("title: \(title)")
            lines.append("---")
        }
        lines.append(contentsOf: themePreamble)
        lines.append("flowchart LR")

        var allocator = MermaidIDAllocator()
        var idMap: [String: String] = [:]
        for node in diagram.nodes {
            idMap[node.id] = allocator.id(for: node.id)
        }
        lines.append(
            contentsOf: PackageProjectSubgraphs().lines(nodes: diagram.nodes) { node in
                "\(idMap[node.id] ?? node.id)[\"\(nodeLabel(node).mermaidLabelEscaped)\"]"
            })

        let breaches = diagram.stableDependencyBreaches
        var linkIndex = 0
        var linkStyles: [String] = []
        for edge in diagram.edges {
            guard let from = idMap[edge.from], let to = idMap[edge.to] else { continue }
            let isBreach = breaches.contains(edge)
            let label = isBreach ? "\(edge.weight) (SDP)" : "\(edge.weight)"
            // A dotted link is Mermaid's only per-edge shape signal, so it carries the breach the way
            // `style=dashed` does in DOT.
            lines.append(isBreach ? "    \(from) -.->|\(label)| \(to)" : "    \(from) -->|\(label)| \(to)")
            if let color = edgeColor?(edge.from, edge.to) {
                linkStyles.append("    linkStyle \(linkIndex) stroke:\(color),stroke-width:2px")
            }
            linkIndex += 1
        }

        for node in diagram.nodes {
            guard let safe = idMap[node.id] else { continue }
            var style = "    style \(safe) fill:\(node.zoneColorHex)"
            if let border = nodeColor?(node.id) { style += ",stroke:\(border),stroke-width:3px" }
            lines.append(style)
        }
        lines.append(contentsOf: linkStyles)

        return lines.joined(separator: "\n") + "\n"
    }

    private func nodeLabel(_ node: PackageDiagram.Node) -> String {
        let types = node.typeCount == 1 ? "1 type" : "\(node.typeCount) types"
        return """
            \(node.moduleName)
            Ca=\(node.afferentCoupling) Ce=\(node.efferentCoupling)
            I=\(twoDecimals(node.instability)) A=\(twoDecimals(node.abstractness)) \
            D=\(twoDecimals(node.distanceFromMainSequence))
            \(node.mainSequenceZone.label)
            \(types)
            """
    }

    private func twoDecimals(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
