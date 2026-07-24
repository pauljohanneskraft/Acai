import SwiftUI

struct ProjectDetailView: View {
    let projectID: UUID
    @EnvironmentObject var model: ProjectBrowserViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State var addingCodebase = false
    @State private var codebasePendingDeletion: Codebase?
    /// Drives the destructive "Delete Project…" confirmation (B53) — a second, discoverable path
    /// to the same confirmed-safe action the sidebar's context menu already offers.
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
                                Label("Add Codebase", systemImage: "folder.badge.plus")
                            }
                            .accessibilityIdentifier("projectDetail.addCodebaseButton")
                            addDiagramMenu
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add")
                        .accessibilityIdentifier("projectDetail.addMenuButton")
                    }
                } else {
                    // iPad (regular width): room for both actions directly in the nav bar instead
                    // of the persistent header row `projectHeader` uses on macOS.
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            addingCodebase = true
                        } label: {
                            Label("Add Codebase", systemImage: "folder.badge.plus")
                        }
                        .accessibilityIdentifier("projectDetail.addCodebaseButton")
                        addDiagramMenu
                    }
                }
            }
            #endif
            .sheet(isPresented: $addingCodebase) {
                NewCodebaseSheet(projectID: project.id)
                    .environmentObject(model)
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
                .accessibilityIdentifier("projectDetail.codebase.delete.confirmButton")
            } message: { _ in
                Text("This deletes its diagrams and cached analysis. This cannot be undone.")
            }
            .confirmationDialog(
                "Delete \"\(project.title)\"?",
                isPresented: $showDeleteProjectConfirmation
            ) {
                Button("Delete Project", role: .destructive) {
                    model.editing.removeProject(project.id)
                }
                .accessibilityIdentifier("projectDetail.project.delete.confirmButton")
            } message: {
                Text("This deletes all of its codebases and diagrams. This cannot be undone.")
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
                // Editable project header
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
            sectionHeader(title: "Codebases")
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
        Section("Codebases") {
            if sortedCodebases.isEmpty {
                Text("No codebases yet. Tap **+** to add one.")
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
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            Task { await model.editing.reindex(codebaseID: codebase.id) }
                        } label: {
                            Label("Reindex", systemImage: "arrow.clockwise")
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
        Section("Diagrams") {
            if freeformDiagrams.isEmpty {
                Text("No freeform diagrams yet. Tap **+** to add one.")
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
                    .swipeActions(edge: .trailing) {
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

    private var emptyProjectPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.full")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Select a project or diagram")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// `showActions` is `false` for a project with no codebases and no diagrams yet (B52): in that
    /// case `emptyProjectContentState` renders the same two actions itself, larger and centered —
    /// showing them here too would duplicate them "half-heartedly in two places." On iPad these
    /// actions live in the nav bar toolbar instead (room for two real buttons there, unlike
    /// iPhone's collapsed menu) — macOS keeps them here, matching the Mac pattern of persistent,
    /// in-content controls rather than a nav-bar-first design.
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
                    Label("Add codebase", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("projectDetail.addCodebaseButton")
                addDiagramMenu
            }
            #endif
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

}

// MARK: - Codebase Row

extension ProjectDetailView {
    fileprivate func codebaseRow(codebase: Codebase) -> some View {
        Button {
            model.selection = .codebase(codebase.id)
        } label: {
            codebaseRowContent(codebase: codebase)
                // Only the regular-width (`LazyVStack`) call site needs this padding — the compact
                // `List` row reuses `codebaseRowContent` directly and already gets its own row
                // insets from `List`, so baking padding into the shared content would double it up
                // there (the same anti-pattern `deleteProjectSection`'s doc comment already calls
                // out and avoids).
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
                    .accessibilityLabel("Indexed")
                    .help("Indexed")
            } else {
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .accessibilityLabel("Not yet indexed")
                    .help("Not yet indexed")
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    fileprivate func codebaseContextMenu(codebase: Codebase) -> some View {
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
            codebasePendingDeletion = codebase
        } label: {
            Label("Delete", systemImage: "trash")
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
