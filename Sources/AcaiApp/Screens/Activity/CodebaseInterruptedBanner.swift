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
            banner(record: record, work: work)
        }
        if work != .reindex {
            staleBanner
        }
    }

    private func banner(
        record: InterruptedOperationRecord, work: InterruptedOperationRecord.CodebaseWork
    ) -> some View {
        let isResuming = phase(work).isInFlight
        return InterruptionBannerLayout(systemImage: record.kind.systemImage) {
            Text(localized: title(for: work))
                .font(.subheadline)
                .foregroundStyle(.orange)
            Text(localized: caption(for: work))
                .font(.caption)
                .foregroundStyle(.secondary)
        } actions: {
            dismissButton(record, identifier: "dismissButton", isResuming: isResuming)
            resumeButton(work, identifier: "resumeButton", isResuming: isResuming)
        }
        .accessibilityIdentifier("codebaseDetail.interruptedBanner")
        .contextMenu {
            resumeButton(work, identifier: "menuResumeButton", isResuming: isResuming)
            dismissButton(record, identifier: "menuDismissButton", isResuming: isResuming)
        }
    }

    private func resumeButton(
        _ work: InterruptedOperationRecord.CodebaseWork, identifier: String, isResuming: Bool
    ) -> some View {
        Button {
            resume(work)
        } label: {
            Label(actionTitle(for: work), systemImage: "arrow.clockwise")
        }
        .disabled(isResuming)
        .accessibilityIdentifier("codebaseDetail.interruptedBanner.\(identifier)")
    }

    private func dismissButton(
        _ record: InterruptedOperationRecord, identifier: String, isResuming: Bool
    ) -> some View {
        Button {
            activityCenter.discardInterruptedOperation(record.id)
        } label: {
            Label(.app("View.CodebaseInterruptedBanner.Dismiss"), systemImage: "xmark")
        }
        .disabled(isResuming)
        .accessibilityIdentifier("codebaseDetail.interruptedBanner.\(identifier)")
    }

    private func title(for work: InterruptedOperationRecord.CodebaseWork) -> LocalizedStringResource {
        switch work {
        case .reindex:
            .app("View.CodebaseInterruptedBanner.IndexingDidNotFinish")
        case .pull:
            .app("View.CodebaseInterruptedBanner.PullDidNotFinish")
        case .switchRef(let ref, _):
            .app("View.CodebaseInterruptedBanner.SwitchDidNotFinish \(ref)")
        case .exportAtlas:
            .app("View.CodebaseInterruptedBanner.ExportDidNotFinish")
        }
    }

    /// An export wrote nothing, so the codebase itself is not what may be out of date.
    private func caption(for work: InterruptedOperationRecord.CodebaseWork) -> LocalizedStringResource {
        switch work {
        case .reindex, .pull, .switchRef:
            .app("View.CodebaseInterruptedBanner.MayBeOutOfDate")
        case .exportAtlas:
            .app("View.CodebaseInterruptedBanner.ExportNotSaved")
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
        case .exportAtlas:
            .app("View.CodebaseInterruptedBanner.ExportAtlas")
        }
    }
}
