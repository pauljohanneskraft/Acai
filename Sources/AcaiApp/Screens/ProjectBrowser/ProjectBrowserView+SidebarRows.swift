import SwiftUI

// Carved out of `ProjectBrowserView` to keep that file under the project's file-length limit,
// matching how `ProjectBrowserView+Repositories.swift` already does the same for the Repositories
// section. `projectRow(project:)` is called from `sidebarContent` in the main file, so it (unlike
// the other helpers here, only called from within this same extension) can't stay `fileprivate`.
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
