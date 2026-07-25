import SwiftUI

/// Split out of `ProjectDetailView` to keep that type's body under SwiftLint's `type_body_length`
/// limit: a destructive button at the bottom of the screen, alongside the existing sidebar
/// context-menu path to the same action.
extension ProjectDetailView {
    /// A plain destructive row/button — no padding baked in, so it composes correctly in both call
    /// sites: a native `List` row in `compactContent` (which already applies its own insets — extra
    /// padding here would double up), and `regularContent`'s `ScrollView`, which adds its own
    /// padding at the call site instead.
    var deleteProjectSection: some View {
        Button(role: .destructive) {
            showDeleteProjectConfirmation = true
        } label: {
            // A plain `Label` sizes its icon to the text's own line height, which is narrower than
            // the 32×32 icon frame `codebaseRowContent`/`freeformDiagramRowContent` use above it —
            // matching that frame here is what makes this row's text start at the same leading
            // position as the rows above it, instead of looking misaligned against them.
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.title2)
                    .frame(width: 32, height: 32)
                Text("Delete Project…")
            }
            .foregroundStyle(.red)
            .accessibilityElement(children: .combine)
        }
        // Without this, the platform default button chrome (a bordered/padded push button on
        // macOS) both grows the row taller than the ones above and shifts its content inward,
        // breaking the icon-frame alignment this view's own doc comment above describes.
        .buttonStyle(.plain)
        .accessibilityIdentifier("projectDetail.deleteProjectButton")
    }
}
