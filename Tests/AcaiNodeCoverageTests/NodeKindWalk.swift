import AcaiTreeSitter

/// Collects a tree's named node kinds and, for each kind the inventory calls extracted, one
/// occurrence per name that node declares.
struct NodeKindWalk {
    let inventory: NodeKindInventory
    let context: SourceFileContext

    func facts(in root: Node) -> NodeKindCorpus.Facts {
        var facts = NodeKindCorpus.Facts()
        root.walkPreorder { node in
            guard node.isNamed, let kind = node.nodeType else { return }
            facts.kinds.insert(kind)
            if kind == "ERROR" || node.isMissing {
                facts.hasParseError = true
            }
            guard let extracted = inventory.extracted[kind] else { return }
            let names = extracted.name.names(of: node, in: context)
            guard !names.isEmpty else {
                facts.unreadableNames.insert(kind)
                return
            }
            facts.occurrences += occurrences(of: kind, at: node, names: names)
        }
        return facts
    }

    private func occurrences(
        of kind: String, at node: Node, names: [(name: String, line: Int)]
    ) -> [NodeKindCorpus.Occurrence] {
        let enclosing = enclosingExtractedKind(of: node)
        let nodeLine = node.location(in: context).line
        return names.map { name, line in
            NodeKindCorpus.Occurrence(
                kind: kind,
                enclosing: enclosing,
                name: name,
                headerLines: min(nodeLine, line)...max(nodeLine, line)
            )
        }
    }

    private func enclosingExtractedKind(of node: Node) -> String? {
        var ancestor = node.parent
        while let candidate = ancestor {
            if let kind = candidate.nodeType, inventory.extracted[kind] != nil {
                return kind
            }
            ancestor = candidate.parent
        }
        return nil
    }
}
