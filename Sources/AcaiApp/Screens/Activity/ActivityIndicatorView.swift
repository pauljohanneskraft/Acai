import SwiftUI

struct ActivityIndicatorView: View {
    @ObservedObject var activityCenter: ActivityCenter
    @State private var isExpanded = false

    var body: some View {
        Button {
            isExpanded = true
        } label: {
            iconLabel
        }
        .help(
            activityCenter.operations.isEmpty
                ? "No operations in progress"
                : "\(activityCenter.operations.count) in progress")
        .accessibilityIdentifier("activity.indicatorButton")
        .popover(isPresented: $isExpanded) {
            ActivityOperationListView(activityCenter: activityCenter)
                #if os(iOS)
                .presentationCompactAdaptation(.sheet)
                #endif
        }
    }

    @ViewBuilder
    private var iconLabel: some View {
        if activityCenter.operations.isEmpty {
            Label(.app("View.ActivityIndicatorView.Activity"), systemImage: "circle")
                .labelStyle(.iconOnly)
        } else {
            let running = activityCenter.operations.count
            Label(
                .app("View.ActivityIndicatorView.ActivityProgress \(running)"), systemImage: "circle.dotted"
            )
                .labelStyle(.iconOnly)
                .symbolEffect(.pulse)
                .overlay(alignment: .topTrailing) {
                    Text(.app("View.ActivityIndicatorView.RunningCount \(activityCenter.operations.count)"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Circle().fill(.blue))
                        .offset(x: 8, y: -8)
                        .accessibilityHidden(true)
                }
        }
    }
}

private struct ActivityOperationListView: View {
    @ObservedObject var activityCenter: ActivityCenter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if activityCenter.operations.isEmpty {
                    ContentUnavailableView {
                        Label(
                            .app("View.ActivityOperationListView.NothingInProgress"),
                            systemImage: "checkmark.circle"
                        )
                    } description: {
                        Text(.app("View.ActivityOperationListView.ReindexingFetchingCloningWill"))
                    }
                    .accessibilityIdentifier("activity.emptyState")
                } else {
                    List(activityCenter.operations) { operation in
                        ActivityOperationRow(activityCenter: activityCenter, operation: operation)
                    }
                }
            }
            .navigationTitle(.app("View.ActivityOperationListView.Activity"))
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.app("View.ActivityOperationListView.Done")) { dismiss() }
                        .accessibilityIdentifier("activity.doneButton")
                }
            }
            #endif
        }
        .frame(minWidth: 320, minHeight: 200)
    }
}

private struct ActivityOperationRow: View {
    @ObservedObject var activityCenter: ActivityCenter
    let operation: ActivityOperation

    var body: some View {
        HStack {
            Image(systemName: operation.kind.systemImage)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(localized: operation.title)
                if let progress = operation.progress {
                    ProgressView(value: progress)
                } else {
                    // No operation reports real byte/object progress yet; indeterminate is honest, not fabricated.
                    ProgressView()
                        .controlSize(.small)
                }
            }
            Spacer()
            Button {
                activityCenter.cancel(operation.id)
            } label: {
                Label(.app("View.ActivityOperationRow.Cancel"), systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(.app("View.ActivityOperationRow.Cancel"))
            .accessibilityLabel(.app("View.ActivityOperationRow.CancelOperation \(operation.title)"))
            .accessibilityIdentifier("activity.cancelButton.\(operation.id)")
        }
        .accessibilityIdentifier("activity.row.\(operation.id)")
    }
}
