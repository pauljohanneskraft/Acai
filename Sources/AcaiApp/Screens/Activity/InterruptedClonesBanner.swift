import SwiftUI

/// Reports clones into this project that were still running when the app last stopped, so never added their codebase.
struct InterruptedClonesBanner: View {
    @ObservedObject var activityCenter: ActivityCenter
    let projectID: UUID
    let retry: (InterruptedOperationRecord) -> Void

    var body: some View {
        ForEach(activityCenter.interruptedClones(inProject: projectID)) { record in
            if case .clone(let request) = record.resumption {
                row(record: record, request: request)
            }
        }
    }

    private func row(
        record: InterruptedOperationRecord, request: InterruptedOperationRecord.RemoteCloneRequest
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: record.kind.systemImage)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: .spacingXXS) {
                Text(.app("View.InterruptedClonesBanner.DidNotFinish \(request.name)"))
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                Text(.app("View.InterruptedClonesBanner.NotAdded"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                activityCenter.discardInterruptedOperation(record.id)
            } label: {
                Label(.app("View.InterruptedClonesBanner.Dismiss"), systemImage: "xmark")
            }
            .accessibilityIdentifier("projectDetail.interruptedClone.\(record.id).dismissButton")
            Button {
                retry(record)
            } label: {
                Label(.app("View.InterruptedClonesBanner.RetryClone"), systemImage: "arrow.clockwise")
            }
            .accessibilityIdentifier("projectDetail.interruptedClone.\(record.id).retryButton")
        }
        .padding(.spacingS)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projectDetail.interruptedClone.\(record.id)")
    }
}
