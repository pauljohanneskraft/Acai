import SwiftUI

struct ProjectBrowserView: View {
    @StateObject private var model = ProjectBrowserViewModel()
    @State private var newProjectPresented = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var sidebarSelection: SidebarItem?
    @State private var collapsedProjects = Set<UUID>()
    @State private var renamingDiagramID: UUID?
    @State private var renamingText: String = ""

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
                .navigationTitle("Projects")
        } detail: {
            detailContent
                .containerBackground(.windowBackground, for: .window)
        }
        .onChange(of: sidebarSelection) { _, newValue in
            switch newValue {
            case .project(let id):
                model.selection = .project(id)
            case .codebase(let id):
                model.selection = .codebase(id)
            case .generatedDiagram(let id):
                model.selection = .generatedDiagram(id)
            case .freeformDiagram(let id):
                model.selection = .freeformDiagram(id)
            case .none:
                break
            }
        }
        .onChange(of: model.selection) { _, newValue in
            switch newValue {
            case .project(let id):
                sidebarSelection = .project(id)
            case .codebase(let id):
                sidebarSelection = .codebase(id)
            case .generatedDiagram(let id):
                sidebarSelection = .generatedDiagram(id)
                columnVisibility = .detailOnly
            case .freeformDiagram(let id):
                sidebarSelection = .freeformDiagram(id)
                columnVisibility = .detailOnly
            case .none:
                break
            }
        }
        .sheet(isPresented: $newProjectPresented) {
            NewProjectSheet { title, subtitle in
                model.addProject(title: title, subtitle: subtitle)
            }
        }
    }

    // MARK: - Sidebar (Left Column)

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            List(selection: $sidebarSelection) {
                let projects = model.store.projects.sorted(by: {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                })
                ForEach(projects) { project in
                    DisclosureGroup(
                        isExpanded: Binding {
                            !collapsedProjects.contains(project.id)
                        } set: { newValue in
                            if newValue {
                                collapsedProjects.remove(project.id)
                            } else {
                                collapsedProjects.insert(project.id)
                            }
                        }
                    ) {
                        // Codebases — sorted alphabetically
                        let sortedCodebases = project.codebases.sorted(by: {
                            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                        })
                        ForEach(sortedCodebases) { codebase in
                            Label(codebase.name, systemImage: "folder")
                                .tag(SidebarItem.codebase(codebase.id))
                                .contextMenu {
                                    Button {
                                        Task { await model.reindex(codebaseID: codebase.id) }
                                    } label: {
                                        Label("Reindex", systemImage: "arrow.clockwise")
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        model.removeCodebase(codebase.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }

                        // Generated diagrams — sorted alphabetically
                        let generatedDiagrams = model.generatedDiagramsForProject(project.id)
                            .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
                        ForEach(generatedDiagrams) { diagram in
                            if renamingDiagramID == diagram.id {
                                TextField("Name", text: $renamingText, onCommit: {
                                    model.renameGeneratedDiagram(diagram.id, name: renamingText)
                                    renamingDiagramID = nil
                                })
                                .textFieldStyle(.roundedBorder)
                                .font(.callout)
                            } else {
                                Label(diagram.name, systemImage: diagram.type.systemImage)
                                    .tag(SidebarItem.generatedDiagram(diagram.id))
                                    .contextMenu {
                                        Button {
                                            renamingText = diagram.name
                                            renamingDiagramID = diagram.id
                                        } label: {
                                            Label("Rename", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            model.removeGeneratedDiagram(diagram.id)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }

                        // Freeform diagrams — sorted alphabetically
                        let freeformDiagrams = model.freeformDiagramsForProject(project.id)
                            .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
                        ForEach(freeformDiagrams) { diagram in
                            if renamingDiagramID == diagram.id {
                                TextField("Name", text: $renamingText, onCommit: {
                                    model.renameFreeformDiagram(diagram.id, name: renamingText)
                                    renamingDiagramID = nil
                                })
                                .textFieldStyle(.roundedBorder)
                                .font(.callout)
                            } else {
                                Label(diagram.name, systemImage: FreeformDiagram.systemImage)
                                    .tag(SidebarItem.freeformDiagram(diagram.id))
                                    .contextMenu {
                                        Button {
                                            renamingText = diagram.name
                                            renamingDiagramID = diagram.id
                                        } label: {
                                            Label("Rename", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            model.removeFreeformDiagram(diagram.id)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    } label: {
                        Label(project.title, systemImage: "tray.full")
                            .font(.headline)
                            .tag(SidebarItem.project(project.id))
                            .contextMenu {
                                Button(role: .destructive) {
                                    model.removeProject(project.id)
                                } label: {
                                    Label("Delete Project", systemImage: "trash")
                                }
                            }
                    }
                }
            }

            Divider()

            Button {
                newProjectPresented = true
            } label: {
                Label("New project", systemImage: "plus")
                    .font(.headline)
            }
            .buttonStyle(.plain)
            .padding()
        }
    }

    // MARK: - Detail (Center Column)

    @ViewBuilder
    private var detailContent: some View {
        switch model.selection {
        case .project(let id):
            ProjectDetailView(projectID: id)
                .id(id)
                .environmentObject(model)
        case .codebase(let id):
            CodebaseDetailView(codebaseID: id)
                .id(id)
                .environmentObject(model)
        case .generatedDiagram(let diagramID):
            generatedDiagramDetail(diagramID: diagramID)
        case .freeformDiagram(let diagramID):
            freeformDiagramDetail(diagramID: diagramID)
        case .none:
            emptyState
        }
    }

    @ViewBuilder
    private func generatedDiagramDetail(diagramID: UUID) -> some View {
        if let diagram = model.generatedDiagram(for: diagramID),
           let artifact = model.artifact(for: diagram.codebaseID),
           let codebase = model.codebase(for: diagram.codebaseID) {
            switch diagram.type {
            case .sequenceDiagram:
                SequenceDiagramView(diagram: diagram, artifact: artifact, codebase: codebase)
                    .id(diagramID)
                    .environmentObject(model)
            case .stateDiagram:
                StateDiagramView(diagram: diagram, artifact: artifact, codebase: codebase)
                    .id(diagramID)
                    .environmentObject(model)
            case .packageDiagram:
                PackageDiagramView(diagram: diagram, artifact: artifact, codebase: codebase)
                    .id(diagramID)
                    .environmentObject(model)
            default:
                ClassDiagramView(diagram: diagram, artifact: artifact, codebase: codebase)
                    .id(diagramID)
                    .environmentObject(model)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No analysis available. Reindex the codebase first.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func freeformDiagramDetail(diagramID: UUID) -> some View {
        if model.freeformDiagram(for: diagramID) != nil {
            FreeformDiagramView(diagramID: diagramID)
                .id(diagramID)
                .environmentObject(model)
        } else {
            Text("Diagram not found")
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Select a project or diagram")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Sidebar Item

enum SidebarItem: Hashable {
    case project(UUID)
    case codebase(UUID)
    case generatedDiagram(UUID)
    case freeformDiagram(UUID)
}
