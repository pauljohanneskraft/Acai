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
        if let project, let idx = projectIndex {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Editable project header
                    projectHeader(project: project, index: idx)
                        .padding()

                    Divider()

                    // Codebases section
                    sectionHeader(title: "Codebases") {
                        Button { addingCodebase = true } label: { Label("Add Codebase", systemImage: "plus") }
                            .buttonStyle(.borderless)
                    }

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

                    // Custom diagrams section
                    sectionHeader(title: "Custom Diagrams") {
                        Menu {
                            ForEach(DiagramType.allCases) { type in
                                Button {
                                    if let id = model.addCustomDiagram(
                        to: projectID,
                        name: "New \(type.displayName)",
                        type: type
                    ) {
                                        model.selection = .customDiagram(id)
                                    }
                                } label: {
                                    Label(type.displayName, systemImage: type.systemImage)
                                }
                            }
                        } label: {
                            Label("New Custom Diagram", systemImage: "plus")
                        }
                        .menuStyle(.borderlessButton)
                    }

                    let customDiagrams = model.customDiagramsForProject(projectID)
                        .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
                    if customDiagrams.isEmpty {
                        Text("No custom diagrams yet. Create one above.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                    } else {
                        LazyVStack(spacing: 1) {
                            ForEach(customDiagrams) { diagram in
                                customDiagramRow(diagram: diagram)
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

    private func sectionHeader<Trailing: View>(title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            trailing()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Project Header (Editable)

    private func projectHeader(project: Project, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon picker
            Menu {
                ForEach([
                    "folder", "doc", "desktopcomputer",
                    "iphone", "globe", "server.rack",
                    "shippingbox", "cpu", "hammer",
                    "wrench", "gear", "star", "bookmark"
                ], id: \.self) { symbol in
                    Button {
                        model.store.projects[index].iconSystemName = symbol
                        model.store.save()
                        model.objectWillChange.send()
                    } label: {
                        Label(symbol, systemImage: symbol)
                    }
                }
            } label: {
                Image(systemName: project.iconSystemName)
                    .font(.title)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            VStack(alignment: .leading, spacing: 4) {
                TextField("Project Title", text: Binding(
                    get: { model.store.projects[safe: index]?.title ?? "" },
                    set: { model.store.projects[index].title = $0; model.store.save(); model.objectWillChange.send() }
                ))
                .font(.title2.bold())
                .textFieldStyle(.plain)

                TextField("Subtitle", text: Binding(
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

            Spacer()

            Button(role: .destructive) {
                model.removeProject(project.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Codebase Row

    private func codebaseRow(codebase: Codebase) -> some View {
        Button {
            model.selection = .codebase(codebase.id)
        } label: {
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.blue)
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
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                Task { await model.reindex(codebaseID: codebase.id) }
            } label: {
                Label("Reindex", systemImage: "arrow.clockwise")
            }
            Button { model.exportDOT(for: codebase.id) } label: {
                Label("Export DOT", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button(role: .destructive) {
                model.removeCodebase(codebase.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Custom Diagram Row

    private func customDiagramRow(diagram: CustomDiagram) -> some View {
        Button {
            model.selection = .customDiagram(diagram.id)
        } label: {
            HStack {
                Image(systemName: diagram.diagramType.systemImage)
                    .foregroundStyle(.blue)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(diagram.name)
                        .fontWeight(.medium)
                    Text(diagram.diagramType.displayName)
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
                model.removeCustomDiagram(diagram.id)
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
