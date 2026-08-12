import SwiftUI

/// The global Activity indicator: a toolbar icon (badge count while anything's in flight) that
/// expands to a list of every in-flight operation the `ActivityCenter` knows about, each with a
/// Cancel affordance. Lives directly in `ProjectBrowserView`'s sidebar toolbar, right next to the
/// Diagram Theme picker, on every platform — macOS gets a `.popover`; iPad/iPhone the same content
/// (a `.popover` reads fine on iPad too; iPhone's compact width collapses it to a sheet the same way
/// `CompareOverlayButton` already does, so this reuses that established platform split rather than
/// inventing a second one).
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
            Label("Activity", systemImage: "circle")
                .labelStyle(.iconOnly)
        } else {
            Label("Activity — \(activityCenter.operations.count) in progress", systemImage: "circle.dotted")
                .labelStyle(.iconOnly)
                .symbolEffect(.pulse)
                .overlay(alignment: .topTrailing) {
                    Text("\(activityCenter.operations.count)")
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

/// The expanded list behind the indicator: one named row per in-flight operation, each with a
/// Cancel button, plus a designed empty state — not just the happy "operations exist" path.
private struct ActivityOperationListView: View {
    @ObservedObject var activityCenter: ActivityCenter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if activityCenter.operations.isEmpty {
                    ContentUnavailableView(
                        "Nothing in Progress",
                        systemImage: "checkmark.circle",
                        description: Text("Reindexing, fetching, and cloning will show up here while they run.")
                    )
                    .accessibilityIdentifier("activity.emptyState")
                } else {
                    List(activityCenter.operations) { operation in
                        ActivityOperationRow(activityCenter: activityCenter, operation: operation)
                    }
                }
            }
            .navigationTitle("Activity")
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
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
                Text(operation.title)
                if let progress = operation.progress {
                    ProgressView(value: progress)
                } else {
                    // No operation kind reports real byte/object progress yet (that needs libgit2's
                    // transfer callbacks — a separate, not-yet-built piece of work) — an
                    // indeterminate spinner is the honest state, not a fabricated percentage.
                    ProgressView()
                        .controlSize(.small)
                }
            }
            Spacer()
            Button {
                activityCenter.cancel(operation.id)
            } label: {
                Label("Cancel", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Cancel")
            .accessibilityLabel("Cancel \(operation.title)")
            .accessibilityIdentifier("activity.cancelButton.\(operation.id)")
        }
        .accessibilityIdentifier("activity.row.\(operation.id)")
    }
}
