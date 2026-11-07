import SwiftUI

/// Reports clones into this project that were still running when the app last stopped, so never added their codebase.
struct InterruptedClonesBanner: View {
    @ObservedObject var activityCenter: ActivityCenter
    let projectID: UUID
    let retry: @MainActor (InterruptedOperationRecord) async -> OperationOutcome

    /// Outside the rows, since a retry that lands removes its row.
    @State private var retryPhase: AsyncOperationPhase = .idle
    @State private var retryTask: Task<Void, Never>?

    var body: some View {
        ForEach(activityCenter.interruptedClones(inProject: projectID)) { record in
            if case .clone(let request) = record.resumption {
                row(record: record, request: request)
            }
        }
        if retryPhase != .idle {
            retryStatus
        }
    }

    private func row(
        record: InterruptedOperationRecord, request: InterruptedOperationRecord.RemoteCloneRequest
    ) -> some View {
        let isRetrying = retryPhase.isInFlight || activityCenter.isRedoing(record)
        return InterruptionBannerLayout(systemImage: record.kind.systemImage) {
            Text(.app("View.InterruptedClonesBanner.DidNotFinish \(request.name)"))
                .font(.subheadline)
                .foregroundStyle(.orange)
            Text(.app("View.InterruptedClonesBanner.NotAdded"))
                .font(.caption)
                .foregroundStyle(.secondary)
        } actions: {
            dismissButton(record, identifier: "dismissButton", isRetrying: isRetrying)
            retryButton(record, request: request, identifier: "retryButton", isRetrying: isRetrying)
        }
        // In a compact `List` row, a default-styled button takes taps meant for its neighbour.
        .buttonStyle(.borderless)
        .accessibilityIdentifier("projectDetail.interruptedClone.\(record.id)")
        .contextMenu {
            retryButton(record, request: request, identifier: "menuRetryButton", isRetrying: isRetrying)
            dismissButton(record, identifier: "menuDismissButton", isRetrying: isRetrying)
        }
        .swipeActions(edge: .trailing) {
            dismissButton(record, identifier: "swipeDismissButton", isRetrying: isRetrying)
        }
    }

    private func dismissButton(
        _ record: InterruptedOperationRecord, identifier: String, isRetrying: Bool
    ) -> some View {
        Button {
            activityCenter.discardInterruptedOperation(record.id)
        } label: {
            Label(.app("View.InterruptedClonesBanner.Dismiss"), systemImage: "xmark")
        }
        .disabled(isRetrying)
        .accessibilityIdentifier("projectDetail.interruptedClone.\(record.id).\(identifier)")
    }

    private func retryButton(
        _ record: InterruptedOperationRecord,
        request: InterruptedOperationRecord.RemoteCloneRequest,
        identifier: String,
        isRetrying: Bool
    ) -> some View {
        Button {
            startRetry(record, request: request)
        } label: {
            Label(.app("View.InterruptedClonesBanner.RetryClone"), systemImage: "arrow.clockwise")
        }
        .disabled(isRetrying)
        .accessibilityIdentifier("projectDetail.interruptedClone.\(record.id).\(identifier)")
    }

    private var retryStatus: some View {
        HStack(spacing: .spacingS) {
            AsyncOperationStatusView(identifierPrefix: "projectDetail.retryClone", phase: retryPhase)
            if retryPhase.isInFlight {
                Button(role: .cancel) {
                    retryTask?.cancel()
                } label: {
                    Label(.app("View.InterruptedClonesBanner.Cancel"), systemImage: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("projectDetail.retryClone.cancelButton")
            }
        }
    }

    private func startRetry(
        _ record: InterruptedOperationRecord, request: InterruptedOperationRecord.RemoteCloneRequest
    ) {
        retryPhase = .loading(.app("View.InterruptedClonesBanner.Cloning \(request.name)"))
        retryTask = Task {
            let outcome = await retry(record)
            retryPhase = AsyncOperationPhase(
                outcome, failure: .app("View.InterruptedClonesBanner.CloneFailed \(request.name)"))
        }
    }
}
