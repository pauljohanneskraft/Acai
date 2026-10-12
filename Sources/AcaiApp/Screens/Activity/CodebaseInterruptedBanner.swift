import SwiftUI

/// Reports that an index, clone or fetch for this codebase was still running when the app last
/// stopped. Without it the screen shows the state from before that work started and reads as
/// current, which is the one thing the interruption bar rules out.
struct CodebaseInterruptedBanner: View {
    @ObservedObject var activityCenter: ActivityCenter
    let codebaseID: UUID
    let phase: AsyncOperationPhase
    let resume: () -> Void

    private var record: InterruptedOperationRecord? {
        activityCenter.interruptedOperation(for: .codebase(codebaseID))
    }

    var body: some View {
        if let record {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: record.kind.systemImage)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: .spacingXXS) {
                    Text(.app("View.CodebaseInterruptedBanner.DidNotFinish"))
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    Text(.app("View.CodebaseInterruptedBanner.MayBeOutOfDate"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: resume) {
                    Label(.app("View.CodebaseInterruptedBanner.Reindex"), systemImage: "arrow.clockwise")
                }
                .disabled(phase.isInFlight)
                .accessibilityIdentifier("codebaseDetail.interruptedBanner.reindexButton")
                AsyncOperationStatusView(
                    identifierPrefix: "codebaseDetail.interruptedBanner.reindex", phase: phase)
            }
            .padding(.spacingS)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("codebaseDetail.interruptedBanner")
        }
    }
}
