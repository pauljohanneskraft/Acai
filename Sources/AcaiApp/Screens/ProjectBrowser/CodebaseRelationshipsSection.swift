import SwiftUI
import AcaiCore

/// Section view displaying all relationships in a codebase,
/// sorted by source → target with kind indicators.
struct CodebaseRelationshipsSection: View {
    let artifact: CodeArtifact

    private func displayName(for id: String) -> String {
        artifact.types.first {
            $0.id == id || $0.qualifiedName == id
        }?.name ?? id
    }

    var body: some View {
        CollapsibleSection(title: "Relationships", defaultExpanded: false) {
            SectionCountBadge(text: "\(artifact.relationships.count)")
        } content: {
            let sortedRelationships = artifact.relationships
                // Key on kind and labels too — distinct relationships between the same pair
                // (inheritance + dependency, or differently-labeled associations) must not collapse.
                .removingDuplicates {
                    "\($0.source)|\($0.target)|\($0.kind.rawValue)"
                        + "|\($0.sourceLabel ?? "")|\($0.targetLabel ?? "")|\($0.label ?? "")"
                }
                .sorted {
                    ($0.source, $0.target) < ($1.source, $1.target)
                }
            LazyVStack(spacing: 1) {
                ForEach(Array(sortedRelationships.enumerated()), id: \.offset) { _, rel in
                    relationshipRow(rel: rel)
                }
            }
        }
    }

    private func relationshipRow(rel: Relationship) -> some View {
        HStack(spacing: 8) {
            relationshipKindBadge(rel.kind)
            Text(displayName(for: rel.source))
                .fontWeight(.medium)
            Image(systemName: relationshipArrow(rel.kind))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(displayName(for: rel.target))
                .fontWeight(.medium)
            Spacer()
            Text(rel.kind.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private func relationshipKindBadge(_ kind: Relationship.Kind) -> some View {
        let color: Color = {
            switch kind {
            case .inheritance:
                return .blue
            case .conformance:
                return .orange
            case .composition:
                return .red
            case .aggregation:
                return .purple
            case .association:
                return .green
            case .dependency:
                return .gray
            case .extension:
                return .brown
            case .nesting:
                return .teal
            }
        }()
        return Circle()
            .fill(color)
            .frame(width: 10, height: 10)
    }

    private func relationshipArrow(_ kind: Relationship.Kind) -> String {
        switch kind {
        case .inheritance:
            return "arrow.up"
        case .conformance:
            return "arrow.up.to.line"
        case .composition:
            return "diamond.fill"
        case .aggregation:
            return "diamond"
        case .association:
            return "arrow.right"
        case .dependency:
            return "arrow.right"
        case .extension:
            return "plus"
        case .nesting:
            return "arrow.down.right"
        }
    }
}
