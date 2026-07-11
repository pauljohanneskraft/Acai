import SwiftUI

struct ProjectDetailView: View {
    let projectID: UUID
    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var addingCodebase = false

    private var project: Project? {
        model.store.projects.first(where: { $0.id == projectID })
    }

    private var projectIndex: Int? {
        model.store.projects.firstIndex(where: { $0.id == projectID })
    }

    var body: some View {
        if let project, let index = projectIndex {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Editable project header
                    projectHeader(project: project, index: index)

                    Divider()

                    sectionHeader(title: "Codebases")

                    let sortedCodebases = project.codebases.sorted(by: {
                        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    })
                    if sortedCodebases.isEmpty {
                        Text("No codebases yet. Add one above.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                    } else {
                        LazyVStack(spacing: 1) {
                            ForEach(sortedCodebases) { codebase in
                                codebaseRow(codebase: codebase)
                            }
                        }
                        .padding(.bottom, 8)
                    }

                    Divider()

                    sectionHeader(title: "Diagrams")

                    let freeformDiagrams = model.freeformDiagramsForProject(projectID)
                        .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
                    if freeformDiagrams.isEmpty {
                        Text("No freeform diagrams yet. Create one above.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                    } else {
                        LazyVStack(spacing: 1) {
                            ForEach(freeformDiagrams) { diagram in
                                freeformDiagramRow(diagram: diagram)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
            .sheet(isPresented: $addingCodebase) {
                NewCodebaseSheet(projectID: project.id)
                    .environmentObject(model)
            }
        } else {
            Text("Project not found")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Section Header

    private func sectionHeader(title: String) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    // MARK: - Project Header (Editable)

    private func projectHeader(project: Project, index: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full")
                .font(.title)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            projectTitleFields(index: index)
            Spacer()
            Button {
                addingCodebase = true
            } label: {
                Label("Add codebase", systemImage: "plus")
            }
            Button {
                if let id = model.freeforms.add(to: projectID, name: "New Freeform Diagram") {
                    model.selection = .freeformDiagram(id)
                }
            } label: {
                Label("Add Diagram", systemImage: "plus")
            }
        }
        .padding()
    }

    private func projectTitleFields(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Project Name", text: Binding(
                get: { model.store.projects[safe: index]?.title ?? "" },
                set: { model.store.projects[index].title = $0; model.store.save(); model.objectWillChange.send() }
            ))
            .font(.title2.bold())
            .textFieldStyle(.plain)

            TextField("Project Description", text: Binding(
                get: { model.store.projects[safe: index]?.subtitle ?? "" },
                set: {
                    model.store.projects[index].subtitle = $0
                    model.store.save()
                    model.objectWillChange.send()
                }
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .textFieldStyle(.plain)
        }
    }

    // MARK: - Codebase Row

    private func codebaseRow(codebase: Codebase) -> some View {
        Button {
            model.selection = .codebase(codebase.id)
        } label: {
            codebaseRowContent(codebase: codebase)
        }
        .buttonStyle(.plain)
        .contextMenu {
            codebaseContextMenu(codebase: codebase)
        }
    }

    private func codebaseRowContent(codebase: Codebase) -> some View {
        HStack {
            Image(systemName: "folder")
                .foregroundStyle(.primary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(codebase.name)
                    .fontWeight(.medium)
                Text(URL(fileURLWithPath: codebase.directoryPath).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let date = codebase.lastIndexed {
                Text(date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if codebase.hasArtifact {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func codebaseContextMenu(codebase: Codebase) -> some View {
        Button {
            Task { await model.editing.reindex(codebaseID: codebase.id) }
        } label: {
            Label("Reindex", systemImage: "arrow.clockwise")
        }
        Button { model.exportDOT(for: codebase.id) } label: {
            Label("Export DOT", systemImage: "square.and.arrow.up")
        }
        Button { model.exportMermaid(for: codebase.id) } label: {
            Label("Export Mermaid", systemImage: "square.and.arrow.up")
        }
        Divider()
        Button(role: .destructive) {
            model.editing.removeCodebase(codebase.id)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Freeform Diagram Row

    private func freeformDiagramRow(diagram: FreeformDiagram) -> some View {
        Button {
            model.selection = .freeformDiagram(diagram.id)
        } label: {
            HStack {
                Image(systemName: FreeformDiagram.systemImage)
                    .foregroundStyle(.primary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(diagram.name)
                        .fontWeight(.medium)
                    Text("Freeform Diagram")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(diagram.lastModified, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                model.freeforms.remove(diagram.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// Safe subscript for array bounds checking.
extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// Make UUID conform to Identifiable for sheet(item:).
extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
