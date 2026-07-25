import SwiftUI

/// Split out of `CodebaseDetailView` to keep that type's body under SwiftLint's `type_body_length`
/// limit — the "discoverable delete path" concern (B53): a destructive button at the bottom of the
/// screen, alongside the existing sidebar context-menu path to the same confirmed-safe action.
extension CodebaseDetailView {
    /// A plain destructive row/button — deliberately not a centered card, so it reads as one more
    /// action in the flow rather than a one-off design, matching the rest of the screen's left
    /// alignment. No padding baked in — the call site applies the same `.padding(.horizontal)` +
    /// `.padding(.vertical, 4)` convention as the sibling sections on this screen (e.g.
    /// `CodebaseTypesSection`, `CodebaseRelationshipsSection`).
    var deleteCodebaseSection: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Label("Delete Codebase…", systemImage: "trash")
                .foregroundStyle(.red)
        }
        .accessibilityIdentifier("codebaseDetail.deleteCodebaseButton")
    }
}
