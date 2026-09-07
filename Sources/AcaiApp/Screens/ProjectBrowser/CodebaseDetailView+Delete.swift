import SwiftUI

extension CodebaseDetailView {
    /// No padding baked in — the call site applies the same `.padding(.horizontal)` +
    /// `.padding(.vertical, 4)` convention as the sibling sections on this screen.
    var deleteCodebaseSection: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Label(.app("View.CodebaseDetailView.DeleteCodebaseEllipsis"), systemImage: "trash")
                .foregroundStyle(.red)
        }
        .accessibilityIdentifier("codebaseDetail.deleteCodebaseButton")
    }
}
