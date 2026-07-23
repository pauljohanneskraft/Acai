import SwiftUI

/// Split out of `ProjectDetailView` to keep that type's body under SwiftLint's `type_body_length`
/// limit — the "discoverable delete path" concern (B53): a destructive button at the bottom of the
/// screen, alongside the existing sidebar context-menu path to the same confirmed-safe action.
extension ProjectDetailView {
    /// A plain destructive row/button — no padding baked in, so it composes correctly in both call
    /// sites: a native `List` row in `compactContent` (which already applies its own insets — extra
    /// padding here would double up), and `regularContent`'s `ScrollView`, which adds its own
    /// padding at the call site instead.
    var deleteProjectSection: some View {
        Button(role: .destructive) {
            showDeleteProjectConfirmation = true
        } label: {
            Label("Delete Project…", systemImage: "trash")
                .foregroundStyle(.red)
        }
        .accessibilityIdentifier("projectDetail.deleteProjectButton")
    }
}
