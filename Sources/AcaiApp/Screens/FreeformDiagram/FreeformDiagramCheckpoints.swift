import SwiftUI

/// Sheet listing a freeform diagram's saved checkpoints: save a new one named/timestamped,
/// restore one (replacing the canvas's current nodes/edges as one undoable step), or delete one.
/// Deliberately not version control — no branching or diffing between checkpoints.
@MainActor
struct FreeformDiagramCheckpointsView: View {
    @ObservedObject var viewModel: FreeformDiagramViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showSaveAlert = false
    @State private var newCheckpointName = ""

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        NavigationStack {
            List {
                if viewModel.checkpoints.isEmpty {
                    ContentUnavailableView(
                        "No Checkpoints",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Save a checkpoint to snapshot this diagram's current nodes and edges.")
                    )
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
            .navigationTitle("Checkpoints")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("checkpoints.doneButton")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newCheckpointName = Self.dateFormatter.string(from: Date())
                        showSaveAlert = true
                    } label: {
                        Label("Save Checkpoint", systemImage: "plus")
                    }
                    .accessibilityIdentifier("checkpoints.saveButton")
                }
            }
            .alert("Save Checkpoint", isPresented: $showSaveAlert) {
                TextField("Name", text: $newCheckpointName)
                    .accessibilityIdentifier("checkpoints.nameField")
                Button("Save") {
                    let name = newCheckpointName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    viewModel.saveCheckpoint(named: name)
                }
                .accessibilityIdentifier("checkpoints.confirmSaveButton")
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func checkpointRow(_ checkpoint: FreeformDiagram.Checkpoint) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(checkpoint.name)
                    .font(.body)
                Text(Self.dateFormatter.string(from: checkpoint.createdDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Restore") {
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
                Label("Delete", systemImage: "trash")
            }
            .accessibilityIdentifier("checkpoints.deleteButton.\(checkpoint.name)")
        }
        .contextMenu {
            Button(role: .destructive) {
                viewModel.deleteCheckpoint(checkpoint.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
