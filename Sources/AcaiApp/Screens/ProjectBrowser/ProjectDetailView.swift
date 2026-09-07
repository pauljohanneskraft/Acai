import SwiftUI

struct ProjectDetailView: View {
    let projectID: UUID
    @EnvironmentObject var model: ProjectBrowserViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State var addingCodebase = false
    @State private var codebasePendingDeletion: Codebase?
    /// Drives the destructive "Delete Project…" confirmation — a second, discoverable path
    /// to the same action the sidebar's context menu already offers.
    @State var showDeleteProjectConfirmation = false

    private var project: Project? {
        model.store.projects.first(where: { $0.id == projectID })
    }

    private var projectIndex: Int? {
        model.store.projects.firstIndex(where: { $0.id == projectID })
    }

    var body: some View {
        if let project, let index = projectIndex {
            Group {
                if horizontalSizeClass == .compact {
                    compactContent(project: project, index: index)
                } else {
                    regularContent(project: project, index: index)
                }
            }
            .navigationTitle(project.title)
            #if !os(macOS)
            .toolbar {
                if horizontalSizeClass == .compact {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                addingCodebase = true
                            } label: {
                                Label(.app("View.ProjectDetailView.AddCodebase"), systemImage: "folder.badge.plus")
                            }
                            .accessibilityIdentifier("projectDetail.addCodebaseButton")
                            addDiagramButton
                            Divider()
                            findingsButton
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(.app("View.ProjectDetailView.Add"))
                        .accessibilityIdentifier("projectDetail.addMenuButton")
                    }
                } else {
                    // iPad (regular width): room for both actions directly in the nav bar instead
                    // of the persistent header row `projectHeader` uses on macOS.
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            addingCodebase = true
                        } label: {
                            Label(.app("View.ProjectDetailView.AddCodebase"), systemImage: "folder.badge.plus")
                        }
                        .accessibilityIdentifier("projectDetail.addCodebaseButton")
                        addDiagramButton
                        findingsButton
                    }
                }
            }
            #endif
            .sheet(isPresented: $addingCodebase) {
                NewCodebaseSheet(projectID: project.id)
                    .environmentObject(model)
            }
            .confirmationDialog(
                .app("View.ProjectDetailView.ConfirmDeleteCodebase \(codebasePendingDeletion?.name ?? "")"),
                isPresented: Binding(
                    get: { codebasePendingDeletion != nil },
                    set: { if !$0 { codebasePendingDeletion = nil } }
                ),
                presenting: codebasePendingDeletion
            ) { codebase in
                Button(.app("View.ProjectDetailView.DeleteCodebase"), role: .destructive) {
                    model.editing.removeCodebase(codebase.id)
                }
                .accessibilityIdentifier("projectDetail.codebase.delete.confirmButton")
            } message: { _ in
                Text(.app("View.ProjectDetailView.DeletesDiagramsCachedAnalysis"))
            }
            .confirmationDialog(
                .app("View.ProjectDetailView.ConfirmDeleteProject \(project.title)"),
                isPresented: $showDeleteProjectConfirmation
            ) {
                Button(.app("View.ProjectDetailView.DeleteProject"), role: .destructive) {
                    model.editing.removeProject(project.id)
                }
                .accessibilityIdentifier("projectDetail.project.delete.confirmButton")
            } message: {
                Text(.app("View.ProjectDetailView.DeletesAllCodebasesDiagrams"))
            }
        } else {
            emptyProjectPlaceholder
        }
    }

    // MARK: - Regular width (iPad, macOS) — unchanged

    private func regularContent(project: Project, index: Int) -> some View {
        let isProjectEmpty = project.codebases.isEmpty
            && model.freeformDiagramsForProject(projectID).isEmpty
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                projectHeader(project: project, index: index, showActions: !isProjectEmpty)

                Divider()
                regularCodebasesAndDiagramsSection(project: project)
                Divider()
                deleteProjectSection
                    .padding(.horizontal)
                    .padding(.vertical, 12)
            }
            // On a wide window, an unconstrained VStack lets `Spacer()`s inside each row stretch
            // until content (e.g. a codebase row's status icon) sits far from the row it belongs
            // to — cap the reading width and center it instead of letting it span the full window.
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func regularCodebasesAndDiagramsSection(project: Project) -> some View {
        let sortedCodebases = project.codebases.sorted(by: {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        })
        let freeformDiagrams = model.freeformDiagramsForProject(projectID)
            .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })

        if sortedCodebases.isEmpty && freeformDiagrams.isEmpty {
            emptyProjectContentState
        } else {
            sectionHeader(title: .app("View.ProjectDetailView.Codebases"))
            if sortedCodebases.isEmpty {
                Text(.app("View.ProjectDetailView.NoCodebasesYetAdd"))
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

            sectionHeader(title: .app("View.ProjectDetailView.Diagrams"))
            if freeformDiagrams.isEmpty {
                Text(.app("View.ProjectDetailView.NoFreeformDiagramsYet"))
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

    // MARK: - Compact width (iPhone)

    private func compactContent(project: Project, index: Int) -> some View {
        List {
            Section {
                projectTitleFields(index: index)
            }
            compactCodebasesSection(project: project)
            compactDiagramsSection()
            Section {
                deleteProjectSection
            }
        }
    }

    @ViewBuilder
    private func compactCodebasesSection(project: Project) -> some View {
        let sortedCodebases = project.codebases.sorted(by: {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        })
        Section(.app("View.ProjectDetailView.Codebases")) {
            if sortedCodebases.isEmpty {
                Text(.app("View.ProjectDetailView.NoCodebasesYetTap"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedCodebases) { codebase in
                    Button {
                        model.selection = .codebase(codebase.id)
                    } label: {
                        codebaseRowContent(codebase: codebase)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("projectDetail.codebaseRow.\(codebase.id)")
                    .contextMenu { codebaseContextMenu(codebase: codebase) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            codebasePendingDeletion = codebase
                        } label: {
                            Label(.app("View.ProjectDetailView.Delete"), systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            Task { await model.editing.reindex(codebaseID: codebase.id) }
                        } label: {
                            Label(.app("View.ProjectDetailView.Reindex"), systemImage: "arrow.clockwise")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func compactDiagramsSection() -> some View {
        let freeformDiagrams = model.freeformDiagramsForProject(projectID)
            .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        Section(.app("View.ProjectDetailView.Diagrams")) {
            if freeformDiagrams.isEmpty {
                Text(.app("View.ProjectDetailView.NoFreeformDiagramsYetTouch"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(freeformDiagrams) { diagram in
                    Button {
                        model.selection = .freeformDiagram(diagram.id)
                    } label: {
                        freeformDiagramRowContent(diagram: diagram)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("projectDetail.freeformDiagramRow.\(diagram.id)")
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            model.freeforms.remove(diagram.id)
                        } label: {
                            Label(.app("View.ProjectDetailView.Delete"), systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var emptyProjectPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.full")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(.app("View.ProjectDetailView.SelectProjectDiagram"))
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Section Header

    private func sectionHeader(title: LocalizedStringResource) -> some View {
        HStack {
            Text(localized: title).font(.headline)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    // MARK: - Project Header (Editable)

    /// `showActions` is `false` for a project with no codebases and no diagrams yet: in that case
    /// `emptyProjectContentState` renders the same two actions itself, larger and centered, so
    /// showing them here too would duplicate them. On iPad these actions live in the nav bar
    /// toolbar instead; macOS keeps them here, matching its persistent in-content controls pattern.
    private func projectHeader(project: Project, index: Int, showActions: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full")
                .font(.title)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            projectTitleFields(index: index)
            Spacer()
            #if os(macOS)
            if showActions {
                Button {
                    addingCodebase = true
                } label: {
                    Label(.app("View.ProjectDetailView.AddCodebase"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("projectDetail.addCodebaseButton")
                addDiagramButton
            }
            findingsButton
                .buttonStyle(.bordered)
            #endif
        }
        .padding()
    }

}

// MARK: - Project Title Fields

private extension ProjectDetailView {
    func projectTitleFields(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(text: Binding(
                get: { model.store.projects[safe: index]?.title ?? "" },
                set: { model.store.projects[index].title = $0; model.store.save(); model.objectWillChange.send() }
            )) {
                Text(.app("View.ProjectDetailView.ProjectName"))
            }
            .font(.title2.bold())
            .textFieldStyle(.plain)

            TextField(text: Binding(
                get: { model.store.projects[safe: index]?.subtitle ?? "" },
                set: {
                    model.store.projects[index].subtitle = $0
                    model.store.save()
                    model.objectWillChange.send()
                }
            )) {
                Text(.app("View.ProjectDetailView.ProjectDescription"))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .textFieldStyle(.plain)
        }
    }
}

// MARK: - Codebase Row

extension ProjectDetailView {
    fileprivate func codebaseRow(codebase: Codebase) -> some View {
        Button {
            model.selection = .codebase(codebase.id)
        } label: {
            codebaseRowContent(codebase: codebase)
                // Only the regular-width (`LazyVStack`) call site needs this padding — the compact
                // `List` row already gets its own row insets, so baking padding into the shared
                // content would double it up there.
                .padding(.horizontal)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("projectDetail.codebaseRow.\(codebase.id)")
        .contextMenu {
            codebaseContextMenu(codebase: codebase)
        }
    }

    fileprivate func codebaseRowContent(codebase: Codebase) -> some View {
        HStack {
            Image(systemName: "folder")
                .font(.title2)
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: codebase.name)
                    .fontWeight(.medium)
                Text(verbatim: URL(fileURLWithPath: codebase.directoryPath).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let date = codebase.lastIndexed {
                Text(date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            CodebaseIndexStatusBadge(activityCenter: model.store.activityCenter, codebase: codebase)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    fileprivate func codebaseContextMenu(codebase: Codebase) -> some View {
        Button {
            Task { await model.editing.reindex(codebaseID: codebase.id) }
        } label: {
            Label(.app("View.ProjectDetailView.ReindexMenu"), systemImage: "arrow.clockwise")
        }
        Button { model.exportDOT(for: codebase.id) } label: {
            Label(.app("View.ProjectDetailView.ExportDOT"), systemImage: "square.and.arrow.up")
        }
        Button { model.exportMermaid(for: codebase.id) } label: {
            Label(.app("View.ProjectDetailView.ExportMermaid"), systemImage: "square.and.arrow.up")
        }
        Button { Task { await model.exportAtlas(for: codebase.id) } } label: {
            Label(.app("View.ProjectDetailView.ExportCodebaseAtlas"), systemImage: "doc.richtext")
        }
        Divider()
        Button(role: .destructive) {
            codebasePendingDeletion = codebase
        } label: {
            Label(.app("View.ProjectDetailView.DeleteMenu"), systemImage: "trash")
        }
    }
}

// MARK: - Freeform Diagram Row

extension ProjectDetailView {
    fileprivate func freeformDiagramRowContent(diagram: FreeformDiagram) -> some View {
        HStack {
            Image(systemName: FreeformDiagram.systemImage)
                .font(.title2)
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: diagram.name)
                    .fontWeight(.medium)
                Text(.app("View.ProjectDetailView.FreeformDiagram"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(diagram.lastModified, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    fileprivate func freeformDiagramRow(diagram: FreeformDiagram) -> some View {
        Button {
            model.selection = .freeformDiagram(diagram.id)
        } label: {
            freeformDiagramRowContent(diagram: diagram)
                // See `codebaseRow`'s matching comment: only the regular-width call site needs
                // this padding, so it's applied here rather than baked into the shared content.
                .padding(.horizontal)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("projectDetail.freeformDiagramRow.\(diagram.id)")
        .contextMenu {
            Button(role: .destructive) {
                model.freeforms.remove(diagram.id)
            } label: {
                Label(.app("View.ProjectDetailView.DeleteMenu"), systemImage: "trash")
            }
        }
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// So `UUID` can drive `sheet(item:)`.
extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
