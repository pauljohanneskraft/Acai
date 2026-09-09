import SwiftUI
import AcaiCore

extension ClassDiagramSidebar {
    /// A dependent already on this canvas re-selects in place (cheap, no diagram switch); one that
    /// isn't goes through `CodeElementReference` resolution, the same "Open in…" mechanism the
    /// codebase-wide relationships/types lists use for cross-diagram navigation.
    @ViewBuilder
    func dependentRow(_ dependent: ImpactAnalysis.Dependent) -> some View {
        let label = HStack {
            Text(verbatim: dependent.qualifiedName)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }

        if viewModel.nodes.contains(where: { $0.id == dependent.id }) {
            Button {
                viewModel.selectNode(dependent.id, extending: false)
            } label: {
                label
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("diagram.inspector.dependentRow.\(dependent.id)")
        } else {
            label
                .openInCodeElement(.type(id: dependent.id), codebase: viewModel.codebase)
                .accessibilityIdentifier("diagram.inspector.dependentRow.\(dependent.id)")
        }
    }
}
