import SwiftUI

struct ProjectBrowserView: View {
    @StateObject private var model = ProjectBrowserViewModel()
    @State private var newProjectPresented = false
    @State private var collapsedProjects = Set<UUID>()
    @State private var renamingDiagramID: UUID?
    @State private var renamingText: String = ""

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationTitle("Projects")
        } detail: {
            detailContent
                .containerBackground(.windowBackground, for: .window)
        }
        .sheet(isPresented: $newProjectPresented) {
            NewProjectSheet { title, subtitle in
                model.editing.addProject(title: title, subtitle: subtitle)
            }
        }
        .modifier(StoreErrorAlert(store: model.store))
    }

    // MARK: - Sidebar (Left Column)

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            List(selection: $model.selection) {
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
                                .tag(ProjectBrowserViewModel.Selection.codebase(codebase.id))
                                .contextMenu {
                                    Button {
                                        Task { await model.editing.reindex(codebaseID: codebase.id) }
                                    } label: {
                                        Label("Reindex", systemImage: "arrow.clockwise")
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        model.editing.removeCodebase(codebase.id)
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
                                    model.diagrams.rename(diagram.id, name: renamingText)
                                    renamingDiagramID = nil
                                })
                                .textFieldStyle(.roundedBorder)
                                .font(.callout)
                            } else {
                                Label(diagram.name, systemImage: diagram.type.systemImage)
                                    .tag(ProjectBrowserViewModel.Selection.generatedDiagram(diagram.id))
                                    .contextMenu {
                                        Button {
                                            renamingText = diagram.name
                                            renamingDiagramID = diagram.id
                                        } label: {
                                            Label("Rename", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            model.diagrams.remove(diagram.id)
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
                                    model.freeforms.rename(diagram.id, name: renamingText)
                                    renamingDiagramID = nil
                                })
                                .textFieldStyle(.roundedBorder)
                                .font(.callout)
                            } else {
                                Label(diagram.name, systemImage: FreeformDiagram.systemImage)
                                    .tag(ProjectBrowserViewModel.Selection.freeformDiagram(diagram.id))
                                    .contextMenu {
                                        Button {
                                            renamingText = diagram.name
                                            renamingDiagramID = diagram.id
                                        } label: {
                                            Label("Rename", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            model.freeforms.remove(diagram.id)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    } label: {
                        Label(project.title, systemImage: "tray.full")
                            .font(.headline)
                            .tag(ProjectBrowserViewModel.Selection.project(project.id))
                            .contextMenu {
                                Button(role: .destructive) {
                                    model.editing.removeProject(project.id)
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
                deltaHosted(diagram: diagram) {
                    PackageDiagramView(
                        diagram: diagram, artifact: artifact, codebase: codebase,
                        comparisonArtifact: model.comparisonArtifact(for: diagram))
                }
            case .callGraph:
                deltaHosted(diagram: diagram) {
                    CallGraphView(
                        diagram: diagram, artifact: artifact, codebase: codebase,
                        comparisonArtifact: model.comparisonArtifact(for: diagram))
                }
            default:
                deltaHosted(diagram: diagram) {
                    ClassDiagramView(
                        diagram: diagram, artifact: artifact, codebase: codebase,
                        comparisonArtifact: model.comparisonArtifact(for: diagram))
                }
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

    /// Wraps a drawable diagram with the delta-comparison bar, loading the git-revision snapshot on
    /// demand and rebuilding the diagram once it (or a changed ref) is available.
    @ViewBuilder
    private func deltaHosted(
        diagram: GeneratedDiagram, @ViewBuilder content: () -> some View
    ) -> some View {
        let loaded = model.comparisonArtifact(for: diagram) != nil
        VStack(spacing: 0) {
            DeltaComparisonBar(diagram: diagram)
            content()
                .id("\(diagram.id)|\(diagram.comparisonGitRef ?? "")|\(loaded)")
        }
        .task(id: "\(diagram.id)|\(diagram.comparisonGitRef ?? "")") {
            await model.ensureComparisonLoaded(for: diagram)
        }
        .environmentObject(model)
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

// MARK: - Store Error Alert

/// Observes the `ProjectStore` directly (it's nested inside the view model, so the parent view
/// doesn't re-render on its changes) and presents the latest persistence/export failure.
private struct StoreErrorAlert: ViewModifier {
    @ObservedObject var store: ProjectStore

    func body(content: Content) -> some View {
        content.alert(item: $store.lastError) { error in
            Alert(
                title: Text("Something went wrong"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
