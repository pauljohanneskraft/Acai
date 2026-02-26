import SwiftUI

struct ProjectDetailView: View {
    let projectID: UUID
    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var addingCodebase = false
    @State private var diagramGenerationTarget: UUID? = nil

    private var project: Project? {
        model.store.projects.first(where: { $0.id == projectID })
    }

    private var projectIndex: Int? {
        model.store.projects.firstIndex(where: { $0.id == projectID })
    }

    var body: some View {
        if let project, let idx = projectIndex {
            VStack(alignment: .leading, spacing: 0) {
                // Editable project header
                projectHeader(project: project, index: idx)
                    .padding()

                Divider()

                // Codebase section header
                HStack {
                    Text("Codebases").font(.headline)
                    Spacer()
                    Button { addingCodebase = true } label: { Label("Add Codebase", systemImage: "plus") }
                        .buttonStyle(.borderless)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Codebase list
                List {
                    ForEach(project.codebases) { codebase in
                        codebaseRow(codebase: codebase)
                    }
                }
                .listStyle(.inset)

                Divider()

                // Stored diagrams section
                if !project.storedDiagrams.isEmpty {
                    HStack {
                        Text("Generated Diagrams").font(.headline)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    List {
                        ForEach(project.storedDiagrams) { diagram in
                            Button {
                                model.selection = .diagram(diagram.id)
                            } label: {
                                HStack {
                                    Image(systemName: diagram.type.systemImage)
                                    VStack(alignment: .leading) {
                                        Text(diagram.name)
                                        Text(diagram.type.displayName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(diagram.lastModified, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    model.removeStoredDiagram(diagram.id)
                                } label: {
                                    Label("Delete Diagram", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }

                // Custom diagrams section
                Divider()

                HStack {
                    Text("Custom Diagrams").font(.headline)
                    Spacer()
                    Menu {
                        ForEach(DiagramType.allCases) { type in
                            Button {
                                if let id = model.addCustomDiagram(to: projectID, name: "New \(type.displayName)", type: type) {
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
                .padding(.horizontal)
                .padding(.vertical, 8)

                if project.customDiagrams.isEmpty {
                    Text("No custom diagrams yet. Create one above.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                } else {
                    List {
                        ForEach(project.customDiagrams) { diagram in
                            Button {
                                model.selection = .customDiagram(diagram.id)
                            } label: {
                                HStack {
                                    Image(systemName: diagram.diagramType.systemImage)
                                    VStack(alignment: .leading) {
                                        Text(diagram.name)
                                        Text(diagram.diagramType.displayName + " (Custom)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(diagram.lastModified, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    model.removeCustomDiagram(diagram.id)
                                } label: {
                                    Label("Delete Diagram", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .sheet(isPresented: $addingCodebase) {
                NewCodebaseSheet(projectID: project.id)
                    .environmentObject(model)
            }
            .sheet(item: $diagramGenerationTarget) { codebaseID in
                DiagramGenerationSheet(projectID: projectID, codebaseID: codebaseID)
                    .environmentObject(model)
            }
        } else {
            Text("Project not found")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Project Header (Editable)

    private func projectHeader(project: Project, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon picker
            Menu {
                ForEach(["folder", "doc", "desktopcomputer", "iphone", "globe", "server.rack", "shippingbox", "cpu", "hammer", "wrench", "gear", "star", "bookmark"], id: \.self) { symbol in
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
                    set: { model.store.projects[index].subtitle = $0; model.store.save(); model.objectWillChange.send() }
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
        HStack {
            Image(systemName: "folder")
            VStack(alignment: .leading) {
                Text(codebase.name)
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

            // Three-dot menu
            Menu {
                Button {
                    model.inspectedCodebaseID = codebase.id
                } label: {
                    Label("Show Details", systemImage: "info.circle")
                }

                Divider()

                Menu("Generate Diagram") {
                    ForEach(DiagramType.allCases) { type in
                        Button {
                            diagramGenerationTarget = codebase.id
                        } label: {
                            Label(type.displayName, systemImage: type.systemImage)
                        }
                        .disabled(codebase.artifact == nil && type != .classDiagram)
                    }
                }

                Divider()

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
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
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

