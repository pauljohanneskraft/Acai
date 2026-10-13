import SwiftUI

/// Reports work on this codebase that was still running when the app last stopped, with the action that redoes it.
struct CodebaseInterruptedBanner: View {
    @ObservedObject var activityCenter: ActivityCenter
    let codebaseID: UUID
    let phase: (InterruptedOperationRecord.Resumption) -> AsyncOperationPhase
    let resume: (InterruptedOperationRecord.Resumption) -> Void

    var body: some View {
        if let record = activityCenter.interruptedOperation(forCodebase: codebaseID) {
            let phase = phase(record.resumption)
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: record.kind.systemImage)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: .spacingXXS) {
                    Text(localized: title(for: record.resumption))
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    Text(.app("View.CodebaseInterruptedBanner.MayBeOutOfDate"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    resume(record.resumption)
                } label: {
                    Label(actionTitle(for: record.resumption), systemImage: "arrow.clockwise")
                }
                .disabled(phase.isInFlight)
                .accessibilityIdentifier("codebaseDetail.interruptedBanner.resumeButton")
                AsyncOperationStatusView(identifierPrefix: "codebaseDetail.interruptedBanner.resume", phase: phase)
            }
            .padding(.spacingS)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("codebaseDetail.interruptedBanner")
        }
    }

    private func title(for resumption: InterruptedOperationRecord.Resumption) -> LocalizedStringResource {
        switch resumption {
        case .reindex, .clone:
            .app("View.CodebaseInterruptedBanner.IndexingDidNotFinish")
        case .pull:
            .app("View.CodebaseInterruptedBanner.PullDidNotFinish")
        case .switchRef(_, let ref, _):
            .app("View.CodebaseInterruptedBanner.SwitchDidNotFinish \(ref)")
        }
    }

    private func actionTitle(for resumption: InterruptedOperationRecord.Resumption) -> LocalizedStringResource {
        switch resumption {
        case .reindex, .clone:
            .app("View.CodebaseInterruptedBanner.Reindex")
        case .pull:
            .app("View.CodebaseInterruptedBanner.Pull")
        case .switchRef(_, let ref, _):
            .app("View.CodebaseInterruptedBanner.SwitchTo \(ref)")
        }
    }
}
