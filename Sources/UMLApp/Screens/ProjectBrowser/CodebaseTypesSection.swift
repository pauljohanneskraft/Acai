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
        CollapsibleSection(title: "Types (\(artifact.types.count))") {
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
            Text(type.accessLevel.rawValue)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 3))
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
