import SwiftUI

/// Deliberately not version control — no branching or diffing between checkpoints.
@MainActor
struct FreeformDiagramCheckpointsView: View {
    @ObservedObject var viewModel: FreeformDiagramViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showSaveAlert = false
    @State private var newCheckpointName = ""

    var body: some View {
        NavigationStack {
            List {
                if viewModel.checkpoints.isEmpty {
                    ContentUnavailableView {
                        Label(
                            .app("View.FreeformDiagramCheckpointsView.NoCheckpoints"),
                            systemImage: "clock.arrow.circlepath"
                        )
                    } description: {
                        Text(.app("View.FreeformDiagramCheckpointsView.SaveCheckpointSnapshotDiagram"))
                    }
                } else {
                    ForEach(viewModel.checkpoints) { checkpoint in
                        checkpointRow(checkpoint)
                    }
                }
            }
            // Without an explicit height, this `List`'s size is driven by its content at the
            // sheet's first layout pass — when that pass happens while `checkpoints` is still
            // empty (every "Save Checkpoint" flow starts from this same sheet), the sheet can get
            // stuck at that small size and never regrow once a checkpoint is added, clipping every
            // row out of view on a later re-presentation. `CompareGitOverlay`'s ref list sidesteps
            // the same class of bug the same way.
            .frame(minHeight: 150, maxHeight: 300)
            .navigationTitle(.app("View.FreeformDiagramCheckpointsView.Checkpoints"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.app("View.FreeformDiagramCheckpointsView.Done")) { dismiss() }
                        .accessibilityIdentifier("checkpoints.doneButton")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newCheckpointName = Date().formatted(date: .abbreviated, time: .shortened)
                        showSaveAlert = true
                    } label: {
                        Label(.app("View.FreeformDiagramCheckpointsView.SaveCheckpoint"), systemImage: "plus")
                    }
                    .accessibilityIdentifier("checkpoints.saveButton")
                }
            }
            .alert(.app("View.FreeformDiagramCheckpointsView.SaveCheckpoint"), isPresented: $showSaveAlert) {
                TextField(text: $newCheckpointName) {
                    Text(.app("View.FreeformDiagramCheckpointsView.Name"))
                }
                .accessibilityIdentifier("checkpoints.nameField")
                Button(.app("View.FreeformDiagramCheckpointsView.Save")) {
                    let name = newCheckpointName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    viewModel.saveCheckpoint(named: name)
                }
                .accessibilityIdentifier("checkpoints.confirmSaveButton")
                Button(.app("View.FreeformDiagramCheckpointsView.Cancel"), role: .cancel) {}
            }
        }
    }

    private func checkpointRow(_ checkpoint: FreeformDiagram.Checkpoint) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: checkpoint.name)
                    .font(.body)
                Text(verbatim: checkpoint.createdDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(.app("View.FreeformDiagramCheckpointsView.Restore")) {
                viewModel.restoreCheckpoint(checkpoint.id)
                dismiss()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("checkpoints.restoreButton.\(checkpoint.name)")
        }
        .accessibilityIdentifier("checkpoints.row.\(checkpoint.name)")
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                viewModel.deleteCheckpoint(checkpoint.id)
            } label: {
                Label(.app("View.FreeformDiagramCheckpointsView.Delete"), systemImage: "trash")
            }
            .accessibilityIdentifier("checkpoints.deleteButton.\(checkpoint.name)")
        }
        .contextMenu {
            Button(role: .destructive) {
                viewModel.deleteCheckpoint(checkpoint.id)
            } label: {
                Label(.app("View.FreeformDiagramCheckpointsView.Delete"), systemImage: "trash")
            }
        }
    }
}
