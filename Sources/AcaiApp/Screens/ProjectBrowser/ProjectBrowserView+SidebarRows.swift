import SwiftUI

// `projectRow(project:)` is called from `sidebarContent` in the main file, so it (unlike the other
// helpers here, only called from within this same extension) can't stay `fileprivate`.
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
        addressMenuItems(for: .project(project.id), idPrefix: "sidebar.project.\(project.id)")
        Divider()
        Button(role: .destructive) {
            projectPendingDeletion = project
        } label: {
            Label(.app("View.ProjectBrowserView.DeleteProjectMenu"), systemImage: "trash")
        }
    }

    @ViewBuilder
    func projectRow(project: Project) -> some View {
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
                .modifier(FolderDropTarget(projectID: project.id, model: model))
        }
        #else
        // DisclosureGroup's label swallows every tap on iOS (no separate hit-target for the
        // triangle), so `List(selection:)` never sees the tap and the project can't be selected.
        // A real Section (title as header) sidesteps that and gives codebases/diagrams a visible
        // group boundary. Section headers aren't selectable rows, so header actions are plain
        // Buttons instead of `.tag()`-based selection.
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
            .modifier(FolderDropTarget(projectID: project.id, model: model))
        }
        #endif
    }

    @ViewBuilder
    fileprivate func codebaseRows(project: Project) -> some View {
        let sortedCodebases = project.codebases.sorted(byLocalizedName: \.name)
        ForEach(sortedCodebases) { codebase in
            if renamingCodebaseID == codebase.id {
                renameField(identifier: "sidebar.codebase.renameField") {
                    model.editing.updateCodebase(id: codebase.id, name: $0)
                }
            } else {
                codebaseRow(codebase: codebase)
            }
        }
    }

    fileprivate func codebaseRow(codebase: Codebase) -> some View {
        SidebarCodebaseRow(activityCenter: model.store.activityCenter, codebase: codebase)
            .tag(ProjectBrowserViewModel.Selection.codebase(codebase.id))
            .help(codebase.name)
            .accessibilityIdentifier("sidebar.codebase.\(codebase.id)")
            .contextMenu {
                addressMenuItems(for: .codebase(codebase.id), idPrefix: "sidebar.codebase.\(codebase.id)")
                Divider()
                Button {
                    Task { await model.editing.reindex(codebaseID: codebase.id) }
                } label: {
                    Label(.app("View.ProjectBrowserView.Reindex"), systemImage: "arrow.clockwise")
                }
                renameMenuItem(name: codebase.name) { renamingCodebaseID = codebase.id }
                    .accessibilityIdentifier("sidebar.codebase.\(codebase.id).rename")
                Divider()
                Button(role: .destructive) {
                    codebasePendingDeletion = codebase
                } label: {
                    Label(.app("View.ProjectBrowserView.Delete"), systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                if horizontalSizeClass == .compact {
                    Button {
                        Task { await model.editing.reindex(codebaseID: codebase.id) }
                    } label: {
                        Label(.app("View.ProjectBrowserView.Reindex"), systemImage: "arrow.clockwise")
                    }
                    .tint(.blue)
                }
            }
            .swipeActions(edge: .trailing) {
                if horizontalSizeClass == .compact {
                    // Not `role: .destructive`: `List` would animate the row out before the confirmation.
                    Button {
                        codebasePendingDeletion = codebase
                    } label: {
                        Label(.app("View.ProjectBrowserView.Delete"), systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
    }

    /// Starting a rename seeds the field with the current name, so ⏎ on an untouched field is a no-op.
    fileprivate func renameMenuItem(name: String, begin: @escaping () -> Void) -> some View {
        Button {
            renamingText = name
            begin()
        } label: {
            Label(.app("View.ProjectBrowserView.Rename"), systemImage: "pencil")
        }
    }

    fileprivate func renameField(
        identifier: String, rename: @escaping (String) -> Void
    ) -> some View {
        SidebarRenameField(text: $renamingText, identifier: identifier, rename: rename) {
            renamingCodebaseID = nil
            renamingDiagramID = nil
        }
    }

    @ViewBuilder
    fileprivate func generatedDiagramRows(project: Project) -> some View {
        let generatedDiagrams = model.generatedDiagramsForProject(project.id)
            .sorted(byLocalizedName: \.name)
        ForEach(generatedDiagrams) { diagram in
            if renamingDiagramID == diagram.id {
                renameField(identifier: "sidebar.generatedDiagram.renameField") {
                    model.diagrams.rename(diagram.id, name: $0)
                }
            } else {
                Label(diagram.name, systemImage: diagram.type.systemImage)
                    .tag(ProjectBrowserViewModel.Selection.generatedDiagram(diagram.id))
                    .help(diagram.name)
                    .contextMenu {
                        addressMenuItems(
                            for: .generatedDiagram(diagram.id), idPrefix: "sidebar.generatedDiagram.\(diagram.id)")
                        Divider()
                        renameMenuItem(name: diagram.name) { renamingDiagramID = diagram.id }
                        Button {
                            if let id = model.diagrams.duplicate(diagram.id) {
                                model.open(.generatedDiagram(id))
                            }
                        } label: {
                            Label(.app("View.ProjectBrowserView.Duplicate"), systemImage: "plus.square.on.square")
                        }
                        .accessibilityIdentifier("sidebar.generatedDiagram.\(diagram.id).duplicate")
                        Button(role: .destructive) {
                            model.diagrams.remove(diagram.id)
                        } label: {
                            Label(.app("View.ProjectBrowserView.Delete"), systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if horizontalSizeClass == .compact {
                            Button(role: .destructive) {
                                model.diagrams.remove(diagram.id)
                            } label: {
                                Label(.app("View.ProjectBrowserView.Delete"), systemImage: "trash")
                            }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    fileprivate func freeformDiagramRows(project: Project) -> some View {
        let freeformDiagrams = model.freeformDiagramsForProject(project.id)
            .sorted(byLocalizedName: \.name)
        ForEach(freeformDiagrams) { diagram in
            if renamingDiagramID == diagram.id {
                renameField(identifier: "sidebar.freeformDiagram.renameField") {
                    model.freeforms.rename(diagram.id, name: $0)
                }
            } else {
                Label(diagram.name, systemImage: FreeformDiagram.systemImage)
                    .tag(ProjectBrowserViewModel.Selection.freeformDiagram(diagram.id))
                    .help(diagram.name)
                    .contextMenu {
                        addressMenuItems(
                            for: .freeformDiagram(diagram.id), idPrefix: "sidebar.freeformDiagram.\(diagram.id)")
                        Divider()
                        renameMenuItem(name: diagram.name) { renamingDiagramID = diagram.id }
                        Button {
                            if let id = model.freeforms.duplicate(diagram.id) {
                                model.open(.freeformDiagram(id))
                            }
                        } label: {
                            Label(.app("View.ProjectBrowserView.Duplicate"), systemImage: "plus.square.on.square")
                        }
                        .accessibilityIdentifier("sidebar.freeformDiagram.\(diagram.id).duplicate")
                        Button(role: .destructive) {
                            model.freeforms.remove(diagram.id)
                        } label: {
                            Label(.app("View.ProjectBrowserView.Delete"), systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if horizontalSizeClass == .compact {
                            Button(role: .destructive) {
                                model.freeforms.remove(diagram.id)
                            } label: {
                                Label(.app("View.ProjectBrowserView.Delete"), systemImage: "trash")
                            }
                        }
                    }
            }
        }
    }
}

private struct SidebarCodebaseRow: View {
    @ObservedObject var activityCenter: ActivityCenter
    let codebase: Codebase

    private var busyOperation: ActivityOperation? { activityCenter.operation(for: .codebase(codebase.id)) }

    var body: some View {
        Label {
            Text(verbatim: codebase.name)
        } icon: {
            if let busyOperation {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(busyOperation.title)
                    .help(busyOperation.title)
            } else {
                Image(systemName: "folder")
            }
        }
    }
}
