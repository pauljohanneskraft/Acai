import SwiftUI
import UniformTypeIdentifiers

public struct ProjectBrowserView: View {
    // Not `private`: `ProjectBrowserView+Repositories.swift`'s and `ProjectBrowserView
    // +SidebarRows.swift`'s extensions (separate files, kept there only to stay under this file's
    // own line-count limit) need to read these too.
    @StateObject var model = ProjectBrowserViewModel()
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    // Shared with `AcaiRootScene`'s macOS ⌘K `Commands` entry — see `QuickOpenPresenter`'s own
    // doc comment for why this can't just be local `@State` on this view. Not `private`:
    // `ProjectBrowserView+QuickOpen.swift`'s extension needs to read it too.
    @EnvironmentObject var quickOpenPresenter: QuickOpenPresenter
    // iPad/iPhone have no `Settings` scene to reach via ⌘, — a gear icon opens the same content
    // as a sheet instead. Shared (not local `@State`) so `NewCodebaseSheet`'s "Sign in to GitHub
    // in Settings" button can open it too — see `SettingsPresenter`'s own doc comment.
    @EnvironmentObject private var settingsPresenter: SettingsPresenter
    // Set by `AcaiRootScene`'s `.onContinueUserActivity`. Not `private`: `ProjectBrowserView+Handoff.swift`
    // needs to read/clear it too.
    @EnvironmentObject var handoffPresenter: HandoffContinuationPresenter
    #if !os(macOS)
    // Same `@AppStorage` key as `DiagramThemeCommands` (macOS menu-bar picker), so this iOS
    // toolbar picker and the macOS menu stay in sync automatically — there's no menu bar on iOS.
    @AppStorage(DiagramThemeSelection.storageKey, store: DiagramThemeSelection.store)
    private var diagramTheme: DiagramThemeSelection = .system
    #endif
    @State private var newProjectPresented = false
    @State var collapsedProjects = Set<UUID>()
    @State var renamingDiagramID: UUID?
    @State var renamingText: String = ""
    @State var projectPendingDeletion: Project?
    @State var codebasePendingDeletion: Codebase?
    #if !os(macOS)
    @State private var showKeyboardShortcuts = false
    #endif

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationTitle(.app("View.ProjectBrowserView.Projects"))
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 400)
                #if !os(macOS)
                .toolbar {
                    if horizontalSizeClass == .compact {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                newProjectPresented = true
                            } label: {
                                Label(.app("View.ProjectBrowserView.NewProject"), systemImage: "plus")
                            }
                            .accessibilityIdentifier("sidebar.newProjectButton")
                        }
                        // iPhone's dedicated search tab/button — iPad instead gets a pinned field
                        // atop the sidebar `List` (see `sidebarContent`), so this only needs to
                        // exist at compact width.
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                quickOpenPresenter.isPresented = true
                            } label: {
                                Label(.app("View.ProjectBrowserView.QuickOpen"), systemImage: "magnifyingglass")
                            }
                            .accessibilityIdentifier("sidebar.quickOpenButton")
                        }
                    }
                    // `.topBarTrailing`, not `.secondaryAction`, for these three — verified against
                    // a real XCUITest run that with more than one `.secondaryAction` sibling item,
                    // iOS collapses all of them into a single system overflow control with no
                    // individually-tappable accessibility element for any one of them (matches
                    // Apple's own documented "may show inside an overflow menu" behavior for that
                    // placement). `.topBarTrailing` renders each as its own reliably-tappable bar
                    // button instead.
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker(.app("View.ProjectBrowserView.DiagramTheme"), selection: $diagramTheme) {
                                ForEach(DiagramThemeSelection.allCases) { option in
                                    Label(option.label, systemImage: option.symbol).tag(option)
                                }
                            }
                            Button {
                                showKeyboardShortcuts = true
                            } label: {
                                Label(.app("View.ProjectBrowserView.KeyboardShortcuts"), systemImage: "keyboard")
                            }
                            .accessibilityIdentifier("sidebar.keyboardShortcutsButton")
                        } label: {
                            Label(.app("View.ProjectBrowserView.DiagramTheme"), systemImage: "paintbrush")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        ActivityIndicatorView(activityCenter: model.store.activityCenter)
                    }
                    // A standalone icon (not nested inside the Diagram Theme `Menu` above) — more
                    // reliably discoverable/tappable than burying it another level deep.
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            settingsPresenter.isPresented = true
                        } label: {
                            Label(.app("View.ProjectBrowserView.Settings"), systemImage: "gear")
                        }
                        .accessibilityIdentifier("sidebar.settingsButton")
                    }
                }
                #endif
        } detail: {
            detailContent
                #if os(macOS)
                .containerBackground(.windowBackground, for: .window)
                #endif
        }
        // macOS has no sidebar-toolbar `Menu` today (the Diagram Theme picker lives in the menu
        // bar via `DiagramThemeCommands` instead — there's no menu bar on iOS, which is why that
        // iOS-only `Menu` above exists at all) — so this is a small dedicated toolbar of its own,
        // rather than inventing a `MenuBarExtra` scene for one icon.
        #if os(macOS)
        .toolbar {
            ToolbarItem {
                ActivityIndicatorView(activityCenter: model.store.activityCenter)
            }
        }
        #endif
        .sheet(isPresented: $newProjectPresented) {
            NewProjectSheet { title, subtitle in
                let id = model.editing.addProject(title: title, subtitle: subtitle)
                model.selection = .project(id)
            }
        }
        .sheet(isPresented: $quickOpenPresenter.isPresented) {
            QuickOpenSheetHost()
                .environmentObject(model)
        }
        .onChange(of: handoffPresenter.pendingTarget) { _, target in resolveHandoffContinuation(target) }
        .task { model.startScheduledRefresh() }
        #if !os(macOS)
        .sheet(isPresented: $showKeyboardShortcuts) {
            KeyboardShortcutsPanel()
        }
        .sheet(isPresented: $settingsPresenter.isPresented) {
            SettingsSheet()
                .environmentObject(model)
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
                model.store.report(.app("Error.ProjectBrowserView.ExportFailed \(error.localizedDescription)"))
            }
            model.pendingExport = nil
        }
        .modifier(StoreErrorAlert(store: model.store, model: model))
        .confirmationDialog(
            .app("View.ProjectBrowserView.ConfirmDeleteProject \(projectPendingDeletion?.title ?? "")"),
            isPresented: Binding(
                get: { projectPendingDeletion != nil },
                set: { if !$0 { projectPendingDeletion = nil } }
            ),
            presenting: projectPendingDeletion
        ) { project in
            Button(.app("View.ProjectBrowserView.DeleteProject"), role: .destructive) {
                model.editing.removeProject(project.id)
            }
            .accessibilityIdentifier("sidebar.project.delete.confirmButton")
        } message: { _ in
            Text(.app("View.ProjectBrowserView.DeletesAllCodebasesDiagrams"))
        }
        .confirmationDialog(
            .app("View.ProjectBrowserView.ConfirmDeleteCodebase \(codebasePendingDeletion?.name ?? "")"),
            isPresented: Binding(
                get: { codebasePendingDeletion != nil },
                set: { if !$0 { codebasePendingDeletion = nil } }
            ),
            presenting: codebasePendingDeletion
        ) { codebase in
            Button(.app("View.ProjectBrowserView.DeleteCodebase"), role: .destructive) {
                model.editing.removeCodebase(codebase.id)
            }
            .accessibilityIdentifier("sidebar.codebase.delete.confirmButton")
        } message: { _ in
            Text(.app("View.ProjectBrowserView.DeletesDiagramsCachedAnalysis"))
        }
    }

    // MARK: - Sidebar (Left Column)

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            #if !os(macOS)
            if horizontalSizeClass != .compact {
                quickOpenSearchFieldProxy
                Divider()
            }
            #endif
            List(selection: $model.selection) {
                let projects = model.store.projects.sorted(by: {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                })
                ForEach(projects) { project in
                    projectRow(project: project)
                }

                repositoriesSection
            }

            // On compact width (iPhone) this action lives in the toolbar instead — a footer button
            // pinned below a short (or empty) list reads as an unexpected floating control there.
            // iPad's wide sidebar keeps this footer, matching macOS.
            if horizontalSizeClass != .compact {
                Divider()

                Button {
                    newProjectPresented = true
                } label: {
                    Label(.app("View.ProjectBrowserView.NewProject"), systemImage: "plus")
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
        case .repository(let remoteURL):
            RepositoryDetailView(remoteURL: remoteURL)
                .id(remoteURL)
                .environmentObject(model)
        case .findings(let projectID):
            FindingsView(projectID: projectID)
                .id(projectID)
                .environmentObject(model)
        case .none:
            emptyState
                .navigationTitle("")
        }
    }

    @ViewBuilder
    private func generatedDiagramDetail(diagramID: UUID) -> some View {
        if let diagram = model.generatedDiagram(for: diagramID),
           let artifact = model.comparisonNewArtifact(for: diagram) ?? model.artifact(for: diagram.codebaseID),
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
                deltaHosted(diagram: diagram) { isComparePresented in
                    PackageDiagramView(
                        diagram: diagram, artifact: artifact, codebase: codebase,
                        isComparePresented: isComparePresented,
                        comparisonArtifact: model.comparisonArtifact(for: diagram))
                }
            case .callGraph:
                deltaHosted(diagram: diagram) { isComparePresented in
                    CallGraphView(
                        diagram: diagram, artifact: artifact, codebase: codebase,
                        isComparePresented: isComparePresented,
                        comparisonArtifact: model.comparisonArtifact(for: diagram))
                }
            case .moduleCoupling, .hotspot, .cycleDiagram:
                // Split into `ProjectBrowserView+AnalysisDiagrams.swift` (own file, own three-way
                // switch) purely to keep this function's body under SwiftLint's line limit.
                analysisDiagramDetail(diagram: diagram, artifact: artifact, codebase: codebase)
                    .id(diagramID)
                    .environmentObject(model)
            default:
                deltaHosted(diagram: diagram) { isComparePresented in
                    ClassDiagramView(
                        diagram: diagram, artifact: artifact, codebase: codebase,
                        isComparePresented: isComparePresented,
                        comparisonArtifact: model.comparisonArtifact(for: diagram))
                }
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(.app("View.ProjectBrowserView.NoAnalysisAvailableReindex"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Wraps a drawable diagram with the delta-comparison overlay button, loading the git-revision
    /// snapshot on demand and rebuilding the diagram once it (or a changed ref) is available.
    @ViewBuilder
    private func deltaHosted(
        diagram: GeneratedDiagram, @ViewBuilder content: @escaping (Binding<Bool>) -> some View
    ) -> some View {
        DeltaHostedDiagramView(diagram: diagram, content: content)
            .environmentObject(model)
    }

    @ViewBuilder
    private func freeformDiagramDetail(diagramID: UUID) -> some View {
        if model.freeformDiagram(for: diagramID) != nil {
            FreeformDiagramView(diagramID: diagramID)
                .id(diagramID)
                .environmentObject(model)
        } else {
            Text(.app("View.ProjectBrowserView.DiagramNotFound"))
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(.app("View.ProjectBrowserView.SelectProjectDiagram"))
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
    @ObservedObject var model: ProjectBrowserViewModel

    /// Drives the picker from view state rather than from the alert's own action: presenting a
    /// `.fileImporter` while the alert is still dismissing silently does nothing. The target is
    /// held separately from the presentation flag, which SwiftUI clears on dismissal — before the
    /// completion handler that needs it runs.
    @State private var isChoosingFolder = false
    @State private var relocationTarget: UUID?

    func body(content: Content) -> some View {
        content
            .alert(item: $store.lastError) { error in
                guard let codebaseID = error.relocatableCodebaseID else {
                    return Alert(
                        title: Text(.app("View.StoreErrorAlert.SomethingWentWrong")),
                        message: Text(verbatim: error.message),
                        dismissButton: .default(Text(.app("View.StoreErrorAlert.OK")))
                    )
                }
                return Alert(
                    title: Text(.app("View.StoreErrorAlert.SomethingWentWrong")),
                    message: Text(verbatim: error.message),
                    primaryButton: .default(Text(.app("View.StoreErrorAlert.ChooseFolder"))) {
                        relocationTarget = codebaseID
                        isChoosingFolder = true
                    },
                    secondaryButton: .cancel()
                )
            }
            .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
                relocate(result: result)
            }
    }

    private func relocate(result: Result<URL, Error>) {
        guard let codebaseID = relocationTarget else { return }
        relocationTarget = nil
        guard let url = try? result.get() else { return }
        do {
            guard url.startAccessingSecurityScopedResource() else {
                throw ScopedResourceAccess.Failure.accessDenied(url.path)
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let bookmark = try SecurityScopedBookmark(resolving: url)
            model.editing.relocateCodebase(id: codebaseID, directoryURL: url, securityScopedBookmark: bookmark)
        } catch {
            store.report(.app("Error.ProjectBrowserView.FolderUnusable \(error.localizedDescription)"))
        }
    }
}
