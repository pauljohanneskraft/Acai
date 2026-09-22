import SwiftUI

extension ProjectDetailView {
    func freeformDiagramRowContent(diagram: FreeformDiagram) -> some View {
        HStack {
            Image(systemName: FreeformDiagram.systemImage)
                .font(.title2)
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
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

    @ViewBuilder
    func freeformDiagramRow(diagram: FreeformDiagram) -> some View {
        if renamingDiagramID == diagram.id {
            renamingField(diagram: diagram)
                .padding(.horizontal)
                .padding(.vertical, Spacing.xs)
        } else {
            Button {
                model.selection = .freeformDiagram(diagram.id)
            } label: {
                freeformDiagramRowContent(diagram: diagram)
                    // See `codebaseRow`'s matching comment: only the regular-width call site needs
                    // this padding, so it's applied here rather than baked into the shared content.
                    .padding(.horizontal)
                    .padding(.vertical, Spacing.xs)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("projectDetail.freeformDiagramRow.\(diagram.id)")
            .contextMenu { freeformDiagramContextMenu(diagram: diagram) }
        }
    }

    func renamingField(diagram: FreeformDiagram) -> some View {
        TextField(text: $renamingText) {
            Text(.app("View.ProjectDetailView.Name"))
        }
        .onSubmit {
            model.freeforms.rename(diagram.id, name: renamingText)
            renamingDiagramID = nil
        }
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("projectDetail.freeformDiagramRow.\(diagram.id).renameField")
    }

    @ViewBuilder
    func freeformDiagramContextMenu(diagram: FreeformDiagram) -> some View {
        AddressMenuItems(
            selection: .freeformDiagram(diagram.id), idPrefix: "projectDetail.freeformDiagramRow.\(diagram.id)")
        Divider()
        Button {
            renamingText = diagram.name
            renamingDiagramID = diagram.id
        } label: {
            Label(.app("View.ProjectDetailView.RenameMenu"), systemImage: "pencil")
        }
        .accessibilityIdentifier("projectDetail.freeformDiagramRow.\(diagram.id).rename")
        Button {
            if let id = model.freeforms.duplicate(diagram.id) {
                model.open(.freeformDiagram(id))
            }
        } label: {
            Label(.app("View.ProjectDetailView.DuplicateMenu"), systemImage: "plus.square.on.square")
        }
        .accessibilityIdentifier("projectDetail.freeformDiagramRow.\(diagram.id).duplicate")
        Button(role: .destructive) {
            model.freeforms.remove(diagram.id)
        } label: {
            Label(.app("View.ProjectDetailView.DeleteMenu"), systemImage: "trash")
        }
        .accessibilityIdentifier("projectDetail.freeformDiagramRow.\(diagram.id).delete")
    }
}
