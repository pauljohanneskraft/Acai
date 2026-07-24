import SwiftUI
import UniformTypeIdentifiers

public struct ProjectBrowserView: View {
    @StateObject private var model = ProjectBrowserViewModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #if !os(macOS)
    // Same `@AppStorage` key as `DiagramThemeCommands` (macOS menu-bar picker), so this iOS
    // toolbar picker and the macOS menu stay in sync automatically — there's no menu bar on iOS.
    @AppStorage(DiagramThemeSelection.storageKey, store: DiagramThemeSelection.store)
    private var diagramTheme: DiagramThemeSelection = .system
    #endif
    @State private var newProjectPresented = false
    @State private var collapsedProjects = Set<UUID>()
    @State private var renamingDiagramID: UUID?
    @State private var renamingText: String = ""
    @State private var projectPendingDeletion: Project?
    @State private var codebasePendingDeletion: Codebase?
    #if !os(macOS)
    @State private var showKeyboardShortcuts = false
    #endif

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationTitle("Projects")
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 400)
                #if !os(macOS)
                .toolbar {
                    if horizontalSizeClass == .compact {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                newProjectPresented = true
                            } label: {
                                Label("New project", systemImage: "plus")
                            }
                            .accessibilityIdentifier("sidebar.newProjectButton")
                        }
                    }
                    ToolbarItem(placement: .secondaryAction) {
                        Menu {
                            Picker("Diagram Theme", selection: $diagramTheme) {
                                ForEach(DiagramThemeSelection.allCases) { option in
                                    Label(option.label, systemImage: option.symbol).tag(option)
                                }
                            }
                            Button {
                                showKeyboardShortcuts = true
                            } label: {
                                Label("Keyboard Shortcuts", systemImage: "keyboard")
                            }
                            .accessibilityIdentifier("sidebar.keyboardShortcutsButton")
                        } label: {
                            Label("Diagram Theme", systemImage: "paintbrush")
                        }
                    }
                }
                #endif
        } detail: {
            detailContent
                #if os(macOS)
                .containerBackground(.windowBackground, for: .window)
                #endif
        }
        .sheet(isPresented: $newProjectPresented) {
            NewProjectSheet { title, subtitle in
                let id = model.editing.addProject(title: title, subtitle: subtitle)
                model.selection = .project(id)
            }
        }
        #if !os(macOS)
        .sheet(isPresented: $showKeyboardShortcuts) {
            KeyboardShortcutsPanel()
        }
        #endif
        .fileExporter(
            isPresented: Binding(
                get: { model.pendingExport != nil },
                set: { if !$0 { model.pendingExport = nil } }
            ),
            document: model.pendingExport.map { ExportDocument(data: $0.data) },
            contentType: model.pendingExport?.contentType ?? .data,
            defaultFilename: model.pendingExport?.filename
        ) { result in
            if case .failure(let error) = result {
                model.store.report("Export failed: \(error.localizedDescription)")
            }
            model.pendingExport = nil
        }
        .modifier(StoreErrorAlert(store: model.store))
        .confirmationDialog(
            "Delete \"\(projectPendingDeletion?.title ?? "")\"?",
            isPresented: Binding(
                get: { projectPendingDeletion != nil },
                set: { if !$0 { projectPendingDeletion = nil } }
            ),
            presenting: projectPendingDeletion
        ) { project in
            Button("Delete Project", role: .destructive) {
                model.editing.removeProject(project.id)
            }
            .accessibilityIdentifier("sidebar.project.delete.confirmButton")
        } message: { _ in
            Text("This deletes all of its codebases and diagrams. This cannot be undone.")
        }
        .confirmationDialog(
            "Delete \"\(codebasePendingDeletion?.name ?? "")\"?",
            isPresented: Binding(
                get: { codebasePendingDeletion != nil },
                set: { if !$0 { codebasePendingDeletion = nil } }
            ),
            presenting: codebasePendingDeletion
        ) { codebase in
            Button("Delete Codebase", role: .destructive) {
                model.editing.removeCodebase(codebase.id)
            }
            .accessibilityIdentifier("sidebar.codebase.delete.confirmButton")
        } message: { _ in
            Text("This deletes its diagrams and cached analysis. This cannot be undone.")
        }
    }

    // MARK: - Sidebar (Left Column)

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            List(selection: $model.selection) {
                let projects = model.store.projects.sorted(by: {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                })
                ForEach(projects) { project in
                    projectRow(project: project)
                }
            }

            // On compact width (iPhone) this action lives in the toolbar instead — a footer button
            // pinned below a short (or empty) list reads as an unexpected floating control there.
            // iPad's wide sidebar keeps this footer, matching macOS.
            if horizontalSizeClass != .compact {
                Divider()

                Button {
                    newProjectPresented = true
                } label: {
                    Label("New project", systemImage: "plus")
                        .font(.headline)
                }
                .buttonStyle(.plain)
                .padding()
                .accessibilityIdentifier("sidebar.newProjectButton")
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
            CodebaseDetailView(codebaseID: id)
                .id(id)
                .environmentObject(model)
        case .generatedDiagram(let diagramID):
            generatedDiagramDetail(diagramID: diagramID)
        case .freeformDiagram(let diagramID):
            freeformDiagramDetail(diagramID: diagramID)
        case .none:
            emptyState
                .navigationTitle("")
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

    /// Wraps a drawable diagram with the delta-comparison overlay button, loading the git-revision
    /// snapshot on demand and rebuilding the diagram once it (or a changed ref) is available.
    ///
    /// `.id(...)` must stay scoped to `content()` alone, not the whole composed view: chaining
    /// `.task`/`.overlay` onto `content().id(...)` directly put them inside that identity boundary,
    /// so picking a new ref tore down and rebuilt `CompareOverlayButton` too — silently resetting
    /// its own `isPresented` state and dismissing the panel the instant a ref was picked (confirmed
    /// empirically). Keeping the overlay button as a stable `ZStack` sibling, with `.task` on the
    /// outer container, keeps its state outside that reset boundary.
    @ViewBuilder
    private func deltaHosted(
        diagram: GeneratedDiagram, @ViewBuilder content: () -> some View
    ) -> some View {
        let loaded = model.comparisonArtifact(for: diagram) != nil
        ZStack(alignment: .topTrailing) {
            content()
                .id("\(diagram.id)|\(diagram.comparisonGitRef ?? "")|\(loaded)")
            CompareOverlayButton(diagram: diagram)
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

// MARK: - Sidebar Rows

extension ProjectBrowserView {
    private func projectExpansionBinding(for project: Project) -> Binding<Bool> {
        Binding(
            get: { !collapsedProjects.contains(project.id) },
            set: { newValue in
                if newValue {
                    collapsedProjects.remove(project.id)
                } else {
                    collapsedProjects.insert(project.id)
                }
            }
        )
    }

    @ViewBuilder
    fileprivate func projectContextMenu(project: Project) -> some View {
        Button(role: .destructive) {
            projectPendingDeletion = project
        } label: {
            Label("Delete Project", systemImage: "trash")
        }
    }

    @ViewBuilder
    fileprivate func projectRow(project: Project) -> some View {
        #if os(macOS)
        DisclosureGroup(isExpanded: projectExpansionBinding(for: project)) {
            codebaseRows(project: project)
            generatedDiagramRows(project: project)
            freeformDiagramRows(project: project)
        } label: {
            Label(project.title, systemImage: "tray.full")
                .font(.headline)
                .tag(ProjectBrowserViewModel.Selection.project(project.id))
                .help(project.title)
                .accessibilityIdentifier("sidebar.project.\(project.id)")
                .contextMenu { projectContextMenu(project: project) }
        }
        #else
        // DisclosureGroup's label swallows every tap for expand/collapse on iOS — unlike
        // macOS's sidebar list style, there's no separate hit-target for the triangle — so a
        // tap here never reaches `List(selection:)` and the project can never be selected.
        // Rendering the project as a real Section (its title as the header) instead of a plain
        // row also gives its codebases/diagrams a visible group boundary — most noticeable right
        // after adding a codebase, which now clearly nests under the project it belongs to.
        // Section headers aren't selectable List rows, so both header actions are plain Buttons
        // with explicit, imperative effects rather than relying on `.tag()`-based row selection.
        Section {
            if !collapsedProjects.contains(project.id) {
                codebaseRows(project: project)
                generatedDiagramRows(project: project)
                freeformDiagramRows(project: project)
            }
        } header: {
            HStack {
                Button {
                    model.selection = .project(project.id)
                } label: {
                    Label(project.title, systemImage: "tray.full")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.project.\(project.id)")
                Spacer()
                Button {
                    projectExpansionBinding(for: project).wrappedValue.toggle()
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(collapsedProjects.contains(project.id) ? 0 : 90))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .contextMenu { projectContextMenu(project: project) }
        }
        #endif
    }

    @ViewBuilder
    fileprivate func codebaseRows(project: Project) -> some View {
        let sortedCodebases = project.codebases.sorted(by: {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        })
        ForEach(sortedCodebases) { codebase in
            Label(codebase.name, systemImage: "folder")
                .tag(ProjectBrowserViewModel.Selection.codebase(codebase.id))
                .help(codebase.name)
                .accessibilityIdentifier("sidebar.codebase.\(codebase.id)")
                .contextMenu {
                    Button {
                        Task { await model.editing.reindex(codebaseID: codebase.id) }
                    } label: {
                        Label("Reindex", systemImage: "arrow.clockwise")
                    }
                    Divider()
                    Button(role: .destructive) {
                        codebasePendingDeletion = codebase
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    if horizontalSizeClass == .compact {
                        Button {
                            Task { await model.editing.reindex(codebaseID: codebase.id) }
                        } label: {
                            Label("Reindex", systemImage: "arrow.clockwise")
                        }
                        .tint(.blue)
                    }
                }
                .swipeActions(edge: .trailing) {
                    if horizontalSizeClass == .compact {
                        Button(role: .destructive) {
                            codebasePendingDeletion = codebase
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
        }
    }

    @ViewBuilder
    fileprivate func generatedDiagramRows(project: Project) -> some View {
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
                    .help(diagram.name)
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
                    .swipeActions(edge: .trailing) {
                        if horizontalSizeClass == .compact {
                            Button(role: .destructive) {
                                model.diagrams.remove(diagram.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    fileprivate func freeformDiagramRows(project: Project) -> some View {
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
                    .help(diagram.name)
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
                    .swipeActions(edge: .trailing) {
                        if horizontalSizeClass == .compact {
                            Button(role: .destructive) {
                                model.freeforms.remove(diagram.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
            }
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
