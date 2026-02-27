import SwiftUI

struct ProjectBrowserView: View {
    @StateObject private var model = ProjectBrowserViewModel()
    @State private var newProjectPresented = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var sidebarSelection: SidebarItem? = nil
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
                .toolbar {
                    ToolbarItemGroup {
                        Button { newProjectPresented = true } label: { Label("New Project", systemImage: "plus") }
                    }
                }
                .navigationTitle("Projects")
        } detail: {
            HSplitView {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            if inspectorAvailable {
                                Button {
                                    withAnimation { model.showInspector.toggle() }
                                } label: {
                                    Label("Inspector", systemImage: "sidebar.trailing")
                                }
                            }
                        }
                    }
                if model.showInspector {
                    inspectorContent
                        .frame(minWidth: 220, idealWidth: 280, maxWidth: 360)
                }
            }
        }
        .onChange(of: sidebarSelection) { newValue in
            switch newValue {
            case .project(let id):
                model.selection = .project(id)
            case .codebase(let id):
                model.selection = .codebase(id)
                model.inspectedCodebaseID = id
                model.showInspector = true
            case .diagram(let id):
                model.selection = .diagram(id)
                model.showInspector = false
            case .customDiagram(let id):
                model.selection = .customDiagram(id)
                model.showInspector = false
            case .none:
                break
            }
        }
        .onChange(of: model.selection) { newValue in
            switch newValue {
            case .project(let id): sidebarSelection = .project(id)
            case .codebase(let id): sidebarSelection = .codebase(id)
            case .diagram(let id): sidebarSelection = .diagram(id)
            case .customDiagram(let id): sidebarSelection = .customDiagram(id)
            case .none: break
            }
        }
        .sheet(isPresented: $newProjectPresented) {
            NewProjectSheet { title, subtitle, icon in
                model.addProject(title: title, subtitle: subtitle, iconSystemName: icon)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNewProject)) { _ in
            newProjectPresented = true
        }
    }
    
    /// Whether the external inspector toggle should be visible for the current selection.
    /// Diagram views embed their own inspector, so we only show the external one for projects/codebases.
    private var inspectorAvailable: Bool {
        switch model.selection {
        case .codebase: return true
        case .project: return true
        default: return false
        }
    }

    // MARK: - Sidebar (Left Column)

    @State private var renamingDiagramID: UUID? = nil
    @State private var renamingText: String = ""

    private var sidebarContent: some View {
        List(selection: $sidebarSelection) {
            ForEach(model.store.projects) { project in
                Section {
                    // Project row
                    Label(project.title, systemImage: project.iconSystemName)
                        .font(.headline)
                        .tag(SidebarItem.project(project.id))
                        .contextMenu {
                            Button(role: .destructive) {
                                model.removeProject(project.id)
                            } label: {
                                Label("Delete Project", systemImage: "trash")
                            }
                        }

                    // Codebases under this project — each codebase has a disclosure for its diagram types
                    if !project.codebases.isEmpty {
                        ForEach(project.codebases) { codebase in
                            DisclosureGroup {
                                // One row per diagram type — generates or opens the stored diagram for this codebase
                                ForEach(DiagramType.allCases) { type in
                                    let existingDiagram = model.storedDiagrams(for: codebase.id).first(where: { $0.type == type })
                                    codebaseDiagramRow(codebase: codebase, project: project, type: type, existingDiagram: existingDiagram)
                                }
                            } label: {
                                Label(codebase.name, systemImage: "folder")
                                    .tag(SidebarItem.codebase(codebase.id))
                            }
                            .contextMenu {
                                Button {
                                    model.inspectedCodebaseID = codebase.id
                                    model.showInspector = true
                                    sidebarSelection = .codebase(codebase.id)
                                } label: {
                                    Label("Show Details", systemImage: "info.circle")
                                }

                                Divider()

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
                    }

                    // Custom diagrams owned by this project
                    let customDiagrams = model.customDiagramsForProject(project.id)
                    if !customDiagrams.isEmpty {
                        ForEach(customDiagrams) { diagram in
                            if renamingDiagramID == diagram.id {
                                TextField("Name", text: $renamingText, onCommit: {
                                    model.renameCustomDiagram(diagram.id, name: renamingText)
                                    renamingDiagramID = nil
                                })
                                .textFieldStyle(.roundedBorder)
                                .font(.callout)
                            } else {
                                Label {
                                    Text(diagram.name)
                                } icon: {
                                    Image(systemName: diagram.diagramType.systemImage)
                                        .foregroundStyle(.orange)
                                }
                                .tag(SidebarItem.customDiagram(diagram.id))
                                .contextMenu {
                                    Button {
                                        renamingText = diagram.name
                                        renamingDiagramID = diagram.id
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {
                                        model.removeCustomDiagram(diagram.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// A single row for a diagram type under a codebase — opens existing or generates on click.
    private func codebaseDiagramRow(codebase: Codebase, project: Project, type: DiagramType, existingDiagram: StoredDiagram?) -> some View {
        Group {
            if let diagram = existingDiagram {
                // Diagram already exists — show it with rename support
                if renamingDiagramID == diagram.id {
                    TextField("Name", text: $renamingText, onCommit: {
                        model.renameStoredDiagram(diagram.id, name: renamingText)
                        renamingDiagramID = nil
                    })
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                } else {
                    Label(diagram.name, systemImage: type.systemImage)
                        .tag(SidebarItem.diagram(diagram.id))
                        .contextMenu {
                            Button {
                                renamingText = diagram.name
                                renamingDiagramID = diagram.id
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                model.removeStoredDiagram(diagram.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            } else {
                // No diagram yet — show a generatable row
                Button {
                    if let id = model.addStoredDiagram(
                        to: project.id,
                        codebaseID: codebase.id,
                        name: "\(codebase.name) — \(type.displayName)",
                        type: type,
                        configuration: DiagramConfiguration()
                    ) {
                        model.selection = .diagram(id)
                    }
                } label: {
                    Label(type.displayName, systemImage: type.systemImage)
                        .foregroundStyle(.secondary)
                }
                .disabled(codebase.artifact == nil)
            }
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
            if let projectID = model.projectID(for: id) {
                ProjectDetailView(projectID: projectID)
                    .id(projectID)
                    .environmentObject(model)
            } else {
                emptyState
            }
        case .diagram(let diagramID):
            storedDiagramDetail(diagramID: diagramID)
        case .customDiagram(let diagramID):
            customDiagramDetail(diagramID: diagramID)
        case .none:
            emptyState
        }
    }

    @ViewBuilder
    private func storedDiagramDetail(diagramID: UUID) -> some View {
        if let diagram = model.storedDiagram(for: diagramID),
           let codebase = model.codebase(for: diagram.codebaseID),
           let artifact = codebase.artifact {
            StoredDiagramView(diagram: diagram, artifact: artifact, codebaseName: codebase.name)
                .id(diagramID)
                .environmentObject(model)
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
    private func customDiagramDetail(diagramID: UUID) -> some View {
        if model.customDiagram(for: diagramID) != nil {
            CustomDiagramEditorView(diagramID: diagramID)
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

    // MARK: - Inspector (Right Column)

    @ViewBuilder
    private var inspectorContent: some View {
        if let codebaseID = model.inspectedCodebaseID,
           model.selection == .codebase(codebaseID) || model.selection == .project(model.projectID(for: codebaseID) ?? UUID()) {
            CodebaseInspectorView(codebaseID: codebaseID)
                .environmentObject(model)
        } else {
            Text("Select a codebase to inspect")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Sidebar Item

enum SidebarItem: Hashable {
    case project(UUID)
    case codebase(UUID)
    case diagram(UUID)
    case customDiagram(UUID)
}

