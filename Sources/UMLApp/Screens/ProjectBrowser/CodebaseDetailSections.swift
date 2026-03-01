import SwiftUI
import UMLCore

/// Section view displaying all types found in a codebase,
/// sorted alphabetically with type-kind badges.
struct CodebaseTypesSection: View {
    let codebase: Codebase
    let artifact: CodeArtifact

    private func displayName(for id: String) -> String {
        artifact.types.first { 
            $0.id == id || $0.qualifiedName == id 
        }?.name ?? id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Types (\(artifact.types.count))")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 12)

            let sortedTypes = artifact.types
                .removingDuplicates(by: \.id)
                .sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            LazyVStack(spacing: 1) {
                ForEach(sortedTypes, id: \.id) { type in
                    typeRow(type: type)
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func typeRow(type: TypeDeclaration) -> some View {
        HStack(spacing: 8) {
            typeKindBadge(type.kind)
            VStack(alignment: .leading, spacing: 1) {
                Text(type.name)
                    .fontWeight(.medium)
                if !type.inheritedTypes.isEmpty {
                    Text(type.inheritedTypes.map { displayName(for: $0.name) }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if !type.members.isEmpty {
                Text("\(type.members.count) members")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let access = type.accessLevel {
                Text(access.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        #if os(macOS)
        .onTapGesture {
            guard let filePath = type.location?.filePath else {
                print("Unknown location of type: \(type.name)")
                return
            }
            let url = URL(filePath: codebase.directoryPath).appending(path: filePath)
            guard FileManager.default.fileExists(atPath: url.path()) else {
                print("File doesn't exist at path: \(url.absoluteString)")
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        #endif
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private static let badgeInfo: [TypeKind: (letter: String, color: Color)] = [
        .class: ("C", .blue), .struct: ("S", .purple),
        .enum: ("E", .green), .protocol: ("P", .orange),
        .interface: ("I", .orange), .trait: ("T", .pink),
        .typeAlias: ("A", .gray), .object: ("O", .teal),
        .extension: ("X", .brown), .annotation: ("@", .red),
        .module: ("M", .indigo), .record: ("R", .cyan),
        .mixin: ("X", .mint)
    ]

    private func typeKindBadge(_ kind: TypeKind) -> some View {
        let info = Self.badgeInfo[kind] ?? ("?", .gray)
        return Text(info.letter)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(info.color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Relationships (\(artifact.relationships.count))")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 12)

            let sortedRelationships = artifact.relationships
                .removingDuplicates { "\($0.source)-\($0.target)" }
                .sorted {
                    ($0.source, $0.target) < ($1.source, $1.target)
                }
            LazyVStack(spacing: 1) {
                ForEach(Array(sortedRelationships.enumerated()), id: \.offset) { _, rel in
                    relationshipRow(rel: rel)
                }
            }
            .padding(.bottom, 8)
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
