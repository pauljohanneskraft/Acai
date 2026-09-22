import SwiftUI
import AcaiCore

struct CodebaseTypesSection: View {
    let codebase: Codebase
    let artifact: CodeArtifact

    private func displayName(for id: String) -> String {
        artifact.types.first {
            $0.id == id || $0.qualifiedName == id
        }?.name ?? id
    }

    var body: some View {
        CollapsibleSection(title: .app("View.CodebaseTypesSection.Types"), defaultExpanded: false) {
            SectionCountBadge(text: .app("View.SectionCountBadge.Count \(artifact.types.count)"))
        } content: {
            let sortedTypes = artifact.types
                .removingDuplicates(by: \.id)
                .sorted(byLocalizedName: \.name)
            LazyVStack(spacing: Spacing.xxs) {
                ForEach(sortedTypes, id: \.id) { type in
                    typeRow(type: type)
                }
            }
        }
    }

    private func typeRow(type: TypeDeclaration) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.s) {
                typeKindBadge(type.kind)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(verbatim: type.name)
                        .fontWeight(.medium)
                    if !type.inheritedTypes.isEmpty {
                        Text(verbatim: type.inheritedTypes.map { displayName(for: $0.name) }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if !type.members.isEmpty {
                    Text(.app("View.CodebaseTypesSection.Members \(type.members.count)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: type.accessLevel.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .openInCodeElement(.type(id: type.id), codebase: codebase, relativePath: type.location?.filePath)
            if let location = type.location {
                ViewSourceButton(codebase: codebase, relativePath: location.filePath)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, Spacing.xs)
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
        return Text(verbatim: info.letter)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(info.color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
