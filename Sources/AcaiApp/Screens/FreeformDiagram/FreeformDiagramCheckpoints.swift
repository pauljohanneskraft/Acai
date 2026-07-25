import SwiftUI

/// Sheet listing a freeform diagram's saved checkpoints (B27): save a new one named/timestamped,
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
            .navigationTitle("Checkpoints")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newCheckpointName = Self.dateFormatter.string(from: Date())
                        showSaveAlert = true
                    } label: {
                        Label("Save Checkpoint", systemImage: "plus")
                    }
                }
            }
            .alert("Save Checkpoint", isPresented: $showSaveAlert) {
                TextField("Name", text: $newCheckpointName)
                Button("Save") {
                    let name = newCheckpointName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    viewModel.saveCheckpoint(named: name)
                }
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
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                viewModel.deleteCheckpoint(checkpoint.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
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
