import SwiftUI

/// Right sidebar inspector for viewing and editing codebase details.
struct CodebaseInspectorView: View {
    let codebaseID: UUID
    @EnvironmentObject private var model: ProjectBrowserViewModel

    private var codebaseBinding: Binding<Codebase>? {
        for i in model.store.projects.indices {
            if let j = model.store.projects[i].codebases.firstIndex(where: { $0.id == codebaseID }) {
                return Binding(
                    get: { self.model.store.projects[i].codebases[j] },
                    set: { self.model.store.projects[i].codebases[j] = $0; self.model.store.save(); self.model.objectWillChange.send() }
                )
            }
        }
        return nil
    }

    private var codebase: Codebase? {
        model.codebase(for: codebaseID)
    }

    var body: some View {
        if let binding = codebaseBinding, let codebase {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection(binding: binding)
                    Divider()
                    pathSection(codebase: codebase)
                    Divider()
                    analysisSection(codebase: codebase)
                    Divider()
                    diagramsSection(codebase: codebase)
                    Divider()
                    actionsSection(codebase: codebase)
                    Spacer()
                }
                .padding()
            }
        } else {
            Text("Codebase not found")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Header

    private func headerSection(binding: Binding<Codebase>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Codebase", systemImage: "folder")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Name", text: binding.name)
                .font(.title3.bold())
                .textFieldStyle(.plain)
        }
    }

    // MARK: - Path

    private func pathSection(codebase: Codebase) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Path").font(.caption).foregroundStyle(.secondary)
            Text(codebase.directoryPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    // MARK: - Analysis

    private func analysisSection(codebase: Codebase) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Analysis").font(.caption).foregroundStyle(.secondary)

            if let artifact = codebase.artifact {
                inspectorRow(label: "Types", value: "\(artifact.types.count)")
                inspectorRow(label: "Relationships", value: "\(artifact.relationships.count)")
                if let date = codebase.lastIndexed {
                    inspectorRow(label: "Last Indexed", value: date.formatted(date: .abbreviated, time: .shortened))
                }
            } else {
                Text("Not indexed yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Diagrams

    private func diagramsSection(codebase: Codebase) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Diagrams").font(.caption).foregroundStyle(.secondary)

            let diagrams = model.storedDiagrams(for: codebase.id)
            if diagrams.isEmpty {
                Text("No diagrams generated")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(diagrams) { diagram in
                    Button {
                        model.selection = .diagram(diagram.id)
                    } label: {
                        HStack {
                            Image(systemName: diagram.type.systemImage)
                                .frame(width: 16)
                            Text(diagram.name)
                                .font(.callout)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Actions

    private func actionsSection(codebase: Codebase) -> some View {
        VStack(spacing: 8) {
            Button {
                Task { await model.reindex(codebaseID: codebase.id) }
            } label: {
                Label("Reindex", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }

            Button {
                model.exportDOT(for: codebase.id)
            } label: {
                Label("Export DOT", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Helpers

    private func inspectorRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.callout)
            Spacer()
            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
