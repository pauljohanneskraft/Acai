import SwiftUI

extension ProjectDetailView {
    var findingsButton: some View {
        Button {
            model.selection = .findings(projectID)
        } label: {
            Label(.app("View.ProjectDetailView.Findings"), systemImage: "list.bullet.clipboard")
        }
        .accessibilityIdentifier("projectDetail.findingsButton")
    }
}
