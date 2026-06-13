import SwiftUI
import UMLCore

/// Main content area view displayed when a codebase is selected in the sidebar.
/// Shows statistics, types, relationships, and diagram generation buttons.
struct CodebaseDetailView: View {
    let codebaseID: UUID
    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var isIndexing = false
    /// Set when the user clicks "Sequence Diagram"; drives the configuration popup.
    @State private var sequenceConfigContext: ConfigContext?
    /// Set when the user clicks "State Diagram"; drives the variable-selection popup.
    @State private var stateConfigContext: ConfigContext?

    /// Identifies the codebase a pending diagram configuration belongs to.
    private struct ConfigContext: Identifiable {
        let projectID: UUID
        let codebaseID: UUID
        let codebaseName: String
        var id: UUID { codebaseID }
    }

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
                        diagramsSection(codebase: codebase, artifact: artifact)
                        Divider()
                        statisticsSection(artifact: artifact)
                        Divider()
                        CodebaseTypesSection(codebase: codebase, artifact: artifact)
                        Divider()
                        CodebaseRelationshipsSection(artifact: artifact)
                    } else {
                        notIndexedSection(codebase: codebase)
                    }
                }
            }
            .sheet(item: $sequenceConfigContext) { context in
                sequenceConfigSheet(for: context)
            }
            .sheet(item: $stateConfigContext) { context in
                stateConfigSheet(for: context)
            }
        } else {
            Text("Codebase not found")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The state-diagram configuration popup, presented when "State Diagram" is clicked.
    @ViewBuilder
    private func stateConfigSheet(for context: ConfigContext) -> some View {
        if let artifact = model.artifact(for: context.codebaseID) {
            StateConfigSheet(
                artifact: artifact,
                onCancel: { stateConfigContext = nil },
                onCreate: { config in
                    let variable = config.typeName.map { "\($0).\(config.variableName)" } ?? config.variableName
                    if let id = model.addGeneratedDiagram(
                        to: context.projectID,
                        codebaseID: context.codebaseID,
                        name: "\(context.codebaseName) — State: \(variable)",
                        content: .stateDiagram(config)
                    ) {
                        model.selection = .generatedDiagram(id)
                    }
                    stateConfigContext = nil
                }
            )
        }
    }

    /// The sequence-diagram configuration popup, presented when "Sequence Diagram" is clicked.
    @ViewBuilder
    private func sequenceConfigSheet(for context: ConfigContext) -> some View {
        if let artifact = model.artifact(for: context.codebaseID) {
            SequenceConfigSheet(
                artifact: artifact,
                onCancel: { sequenceConfigContext = nil },
                onCreate: { config in
                    if let id = model.addGeneratedDiagram(
                        to: context.projectID,
                        codebaseID: context.codebaseID,
                        name: "\(context.codebaseName) — Sequence: \(config.entryTypeName).\(config.entryMethodName)",
                        content: .sequenceDiagram(config)
                    ) {
                        model.selection = .generatedDiagram(id)
                    }
                    sequenceConfigContext = nil
                }
            )
        }
    }

    // MARK: - Header

    private func headerSection(codebase: Codebase) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "folder")
                    .font(.title)
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Codebase Name", text: Binding(
                        get: { codebase.name },
                        set: { model.updateCodebase(id: codebase.id, name: $0) }
                    ))
                    .font(.title2.bold())
                    .textFieldStyle(.plain)

                    Text((codebase.directoryPath as NSString).abbreviatingWithTildeInPath)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer()

                if let date = codebase.lastIndexed {
                    Text("Last indexed: \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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

            HStack(spacing: 12) {
                statisticCard(
                    label: "\(artifact.types.count) Types",
                    icon: "rectangle.3.group",
                    color: .blue
                )
                statisticCard(
                    label: "\(artifact.relationships.count) Relationships",
                    icon: "arrow.triangle.branch",
                    color: .purple
                )
                statisticCard(
                    label: "\(artifact.freestandingFunctions.count) Functions",
                    icon: "function",
                    color: .green
                )
                statisticCard(
                    label: "Coupling: \(couplingFactor(artifact: artifact)) %",
                    icon: "link",
                    color: .orange
                )
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
    }

    private func statisticCard(label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Spacer()

            Image(systemName: icon)
                .font(.title2.bold())
                .foregroundStyle(color)

            Text(label)
                .font(.title3.bold())
                .foregroundStyle(.primary)

            Spacer()
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
        let typeIds = artifact.types.map(\.id)
        let uniquePairs = Set(
            artifact.relationships
                .filter { typeIds.contains($0.source) && typeIds.contains($0.target) }
                .map { "\($0.source)->\($0.target)" }
        )
        let factor = Double(uniquePairs.count) / maxPossible
        return String(format: "%.2f", factor * 100)
    }

    // MARK: - Diagrams

    private func diagramsSection(codebase: Codebase, artifact: CodeArtifact) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagrams")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 12)

            HStack(spacing: 12) {
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
            // Sequence and state diagrams always open their configuration popup
            // (entry point / variable selection) rather than generating immediately.
            if type == .sequenceDiagram {
                sequenceConfigContext = ConfigContext(
                    projectID: projectID, codebaseID: codebase.id, codebaseName: codebase.name
                )
                return
            }
            if type == .stateDiagram {
                stateConfigContext = ConfigContext(
                    projectID: projectID, codebaseID: codebase.id, codebaseName: codebase.name
                )
                return
            }
            if let existing = model.generatedDiagrams(for: codebase.id).first(where: { $0.type == type }) {
                model.selection = .generatedDiagram(existing.id)
            } else if let id = model.addGeneratedDiagram(
                to: projectID,
                codebaseID: codebase.id,
                name: "\(codebase.name) — \(type.displayName)",
                content: GeneratedDiagram.Content(type: type)
            ) {
                model.selection = .generatedDiagram(id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: type.systemImage)
                    .font(.title2.bold())
                Text(type.displayName)
                    .font(.title3.bold())
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
}
