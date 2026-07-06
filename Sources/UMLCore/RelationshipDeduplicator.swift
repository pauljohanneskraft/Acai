/// Collapses a relationship list to its canonical edges: drops exact duplicates, then drops weaker
/// inferred edges where a stronger explicit relationship already covers the same ordered pair. Behaviour
/// lifted off `CodeArtifact` (it was a pair of `static func`s — a namespace in disguise) onto a value
/// you instantiate and ask for the ``reduced(_:)`` list.
struct RelationshipDeduplicator {

    /// Redundant-edge removal followed by exact-duplicate removal — the order the enrichment pipeline
    /// has always used (`deduplicate(removeRedundantEdges(…))`).
    func reduced(_ relationships: [Relationship]) -> [Relationship] {
        deduplicated(withoutRedundantEdges(relationships))
    }

    /// Drops exact-duplicate edges (same source, target and kind), keeping first occurrence.
    private func deduplicated(_ relationships: [Relationship]) -> [Relationship] {
        var seen = Set<String>()
        return relationships.filter { rel in
            seen.insert("\(rel.source)→\(rel.target):\(rel.kind.rawValue)").inserted
        }
    }

    /// Drops weaker inferred edges when a stronger relationship already covers the pair.
    /// Priority: inheritance/conformance/extension > composition/aggregation > dependency.
    private func withoutRedundantEdges(_ relationships: [Relationship]) -> [Relationship] {
        var strongPairs = Set<String>()
        var mediumPairs = Set<String>()
        for rel in relationships {
            let key = "\(rel.source)→\(rel.target)"
            switch rel.kind {
            case .inheritance, .conformance, .extension:
                strongPairs.insert(key)
            case .composition, .aggregation:
                mediumPairs.insert(key)
            default:
                break
            }
        }
        return relationships.filter { rel in
            let key = "\(rel.source)→\(rel.target)"
            switch rel.kind {
            case .composition, .aggregation:
                return !strongPairs.contains(key)
            case .dependency:
                return !strongPairs.contains(key) && !mediumPairs.contains(key)
            default:
                return true
            }
        }
    }
}
