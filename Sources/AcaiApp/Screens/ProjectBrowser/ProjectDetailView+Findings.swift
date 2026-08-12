import SwiftUI

/// Split out of `ProjectDetailView` to keep that type's body under SwiftLint's `type_body_length`
/// limit — the project-level Findings entry point.
extension ProjectDetailView {
    /// Navigates to this project's aggregated Findings view — every quality violation,
    /// dead-code candidate, and health-check parse diagnostic across every codebase in the project,
    /// in one list, instead of buried one codebase at a time inside each codebase's own detail pane.
    var findingsButton: some View {
        Button {
            model.selection = .findings(projectID)
        } label: {
            Label("Findings", systemImage: "list.bullet.clipboard")
        }
        .accessibilityIdentifier("projectDetail.findingsButton")
    }
}
