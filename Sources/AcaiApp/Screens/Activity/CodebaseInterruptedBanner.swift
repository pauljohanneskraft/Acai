import SwiftUI

/// Reports work on this codebase that was still running when the app last stopped, with the action that redoes it.
struct CodebaseInterruptedBanner<StaleBanner: View>: View {
    @ObservedObject var activityCenter: ActivityCenter
    let codebaseID: UUID
    let phase: (InterruptedOperationRecord.CodebaseWork) -> AsyncOperationPhase
    let resume: (InterruptedOperationRecord.CodebaseWork) -> Void
    /// Left out while an interrupted reindex already offers the same Reindex.
    @ViewBuilder let staleBanner: StaleBanner

    var body: some View {
        let record = activityCenter.interruptedOperation(forCodebase: codebaseID)
        let work = record?.resumption.codebaseWork
        if let record, let work {
            banner(work: work, systemImage: record.kind.systemImage)
        }
        if work != .reindex {
            staleBanner
        }
    }

    private func banner(work: InterruptedOperationRecord.CodebaseWork, systemImage: String) -> some View {
        let phase = phase(work)
        return InterruptionBannerLayout(systemImage: systemImage) {
            Text(localized: title(for: work))
                .font(.subheadline)
                .foregroundStyle(.orange)
            Text(.app("View.CodebaseInterruptedBanner.MayBeOutOfDate"))
                .font(.caption)
                .foregroundStyle(.secondary)
        } actions: {
            Button {
                resume(work)
            } label: {
                Label(actionTitle(for: work), systemImage: "arrow.clockwise")
            }
            .disabled(phase.isInFlight)
            .accessibilityIdentifier("codebaseDetail.interruptedBanner.resumeButton")
            AsyncOperationStatusView(identifierPrefix: "codebaseDetail.interruptedBanner.resume", phase: phase)
        }
        .accessibilityIdentifier("codebaseDetail.interruptedBanner")
    }

    private func title(for work: InterruptedOperationRecord.CodebaseWork) -> LocalizedStringResource {
        switch work {
        case .reindex:
            .app("View.CodebaseInterruptedBanner.IndexingDidNotFinish")
        case .pull:
            .app("View.CodebaseInterruptedBanner.PullDidNotFinish")
        case .switchRef(let ref, _):
            .app("View.CodebaseInterruptedBanner.SwitchDidNotFinish \(ref)")
        }
    }

    private func actionTitle(for work: InterruptedOperationRecord.CodebaseWork) -> LocalizedStringResource {
        switch work {
        case .reindex:
            .app("View.CodebaseInterruptedBanner.Reindex")
        case .pull:
            .app("View.CodebaseInterruptedBanner.Pull")
        case .switchRef(let ref, _):
            .app("View.CodebaseInterruptedBanner.SwitchTo \(ref)")
        }
    }
}
