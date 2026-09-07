import SwiftUI

extension ProjectDetailView {
    /// No padding baked in, so it composes correctly in both call sites: a native `List` row in
    /// `compactContent` (which already applies its own insets), and `regularContent`'s
    /// `ScrollView`, which adds its own padding at the call site instead.
    var deleteProjectSection: some View {
        Button(role: .destructive) {
            showDeleteProjectConfirmation = true
        } label: {
            // Matches the 32×32 icon frame `codebaseRowContent`/`freeformDiagramRowContent` use
            // above, so this row's text lines up with theirs instead of a plain `Label`'s
            // line-height-sized icon shifting it out of alignment.
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.title2)
                    .frame(width: 32, height: 32)
                Text(.app("View.ProjectDetailView.DeleteProjectEllipsis"))
            }
            .foregroundStyle(.red)
            .accessibilityElement(children: .combine)
        }
        // Without this, the platform default button chrome grows the row taller than the ones
        // above and shifts its content inward, breaking the icon-frame alignment above.
        .buttonStyle(.plain)
        .accessibilityIdentifier("projectDetail.deleteProjectButton")
    }
}
