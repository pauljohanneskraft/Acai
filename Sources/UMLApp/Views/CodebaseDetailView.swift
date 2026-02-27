import SwiftUI
import UMLCore

/// Main content area view displayed when a codebase is selected in the sidebar.
/// Shows statistics, types, relationships, and diagram generation buttons.
struct CodebaseDetailView: View {
    let codebaseID: UUID
    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var isIndexing = false

    private var codebase: Codebase? {
        model.codebase(for: codebaseID)
    }

    private var artifact: CodeArtifact? {
        model.artifact(for: codebaseID)
    }

    private var projectID: UUID? {
        model.projectID(for: codebaseID)
    }

    var body: some View {
        if let codebase {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection(codebase: codebase)
                    Divider()

                    if let artifact {
                        statisticsSection(artifact: artifact)
                        Divider()
                        diagramsSection(codebase: codebase, artifact: artifact)
                        Divider()
                        typesSection(artifact: artifact)
                        Divider()
                        relationshipsSection(artifact: artifact)
                    } else {
                        notIndexedSection(codebase: codebase)
                    }

                    Divider()
                    actionsSection(codebase: codebase)
                }
            }
        } else {
            Text("Codebase not found")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Header

    private func headerSection(codebase: Codebase) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: "folder.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(codebase.name)
                        .font(.title2.bold())
                    Text(codebase.directoryPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    if let date = codebase.lastIndexed {
                        Text("Last indexed: \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .padding()
    }

    // MARK: - Statistics

    private func statisticsSection(artifact: CodeArtifact) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 12)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                statisticCard(
                    title: "Types",
                    value: "\(artifact.types.count)",
                    icon: "rectangle.3.group",
                    color: .blue
                )
                statisticCard(
                    title: "Relationships",
                    value: "\(artifact.relationships.count)",
                    icon: "arrow.triangle.branch",
                    color: .purple
                )
                statisticCard(
                    title: "Functions",
                    value: "\(artifact.freestandingFunctions.count)",
                    icon: "function",
                    color: .green
                )
                statisticCard(
                    title: "Coupling",
                    value: couplingFactor(artifact: artifact),
                    icon: "link",
                    color: .orange
                )
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }

    private func statisticCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Coupling factor = actual relationships / (types * (types - 1))
    /// A value between 0 and 1; higher means more interconnected.
    private func couplingFactor(artifact: CodeArtifact) -> String {
        let n = artifact.types.count
        guard n > 1 else { return "N/A" }
        let maxPossible = Double(n * (n - 1))
        let uniquePairs = Set(artifact.relationships.map { "\($0.source)->\($0.target)" })
        let factor = Double(uniquePairs.count) / maxPossible
        return String(format: "%.2f", factor)
    }

    // MARK: - Diagrams

    private func diagramsSection(codebase: Codebase, artifact: CodeArtifact) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagrams")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 12)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(DiagramType.allCases) { type in
                    diagramButton(codebase: codebase, type: type)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }

    /// A diagram type button — all look the same regardless of whether a diagram already exists.
    /// Clicking opens the existing diagram or generates a new one.
    private func diagramButton(codebase: Codebase, type: DiagramType) -> some View {
        Button {
            guard let projectID else { return }
            if let existing = model.storedDiagrams(for: codebase.id).first(where: { $0.type == type }) {
                model.selection = .diagram(existing.id)
            } else if let id = model.addStoredDiagram(
                to: projectID,
                codebaseID: codebase.id,
                name: "\(codebase.name) — \(type.displayName)",
                type: type,
                configuration: DiagramConfiguration()
            ) {
                model.selection = .diagram(id)
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: type.systemImage)
                    .font(.title2)
                Text(type.displayName)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Not Indexed

    private func notIndexedSection(codebase: Codebase) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("This codebase has not been indexed yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                isIndexing = true
                Task {
                    await model.reindex(codebaseID: codebase.id)
                    isIndexing = false
                }
            } label: {
                Label("Index Now", systemImage: "arrow.clockwise")
            }
            .disabled(isIndexing)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Types

    private func typesSection(artifact: CodeArtifact) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Types (\(artifact.types.count))")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 12)

            let sortedTypes = artifact.types.sorted(by: {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            })
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
                    Text(type.inheritedTypes.map(\.name).joined(separator: ", "))
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

    // MARK: - Relationships

    private func relationshipsSection(artifact: CodeArtifact) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Relationships (\(artifact.relationships.count))")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 12)

            let sortedRelationships = artifact.relationships.sorted(by: {
                ($0.source, $0.target) < ($1.source, $1.target)
            })
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
            Text(rel.source)
                .fontWeight(.medium)
            Image(systemName: relationshipArrow(rel.kind))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(rel.target)
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
            return "arrow.right.dotted"
        case .extension:
            return "plus"
        case .nesting:
            return "arrow.down.right"
        }
    }

    // MARK: - Actions

    private func actionsSection(codebase: Codebase) -> some View {
        HStack(spacing: 12) {
            Button {
                isIndexing = true
                Task {
                    await model.reindex(codebaseID: codebase.id)
                    isIndexing = false
                }
            } label: {
                Label("Reindex", systemImage: "arrow.clockwise")
            }
            .disabled(isIndexing)

            Button {
                model.exportDOT(for: codebase.id)
            } label: {
                Label("Export DOT", systemImage: "square.and.arrow.up")
            }

            Spacer()
        }
        .padding()
    }
}
