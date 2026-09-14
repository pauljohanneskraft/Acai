import SwiftUI
import AcaiQuality

/// A "Filter" `Form` section shared by every diagram type's Settings tab: the unmodified
/// `SelectorEditor` (the same selector vocabulary `AcaiQuality`'s rules already use, instead of a
/// second, diagram-specific filter) and named, project-wide filter presets.
struct DiagramFilterSection: View {
    @Binding var filter: AcaiQuality.Selector?
    let projectID: UUID

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var presets = FilterPresetList()
    @State private var showSaveAsPreset = false
    @State private var presetName = ""
    @State private var renamingPresetID: UUID?
    @State private var renamingPresetText = ""
    @State private var presetPendingDelete: FilterPreset?
    @State private var presetSavePhase: AsyncOperationPhase = .idle
    @State private var presetSaveError: String?
    /// Chains each save onto the previous one so writes land on disk in the order they were made —
    /// two detached, unserialized saves (e.g. a rename immediately followed by a delete) could
    /// otherwise finish out of order and let the older one silently resurrect what the newer one
    /// removed.
    @State private var pendingPresetSave: Task<Void, Never>?

    var body: some View {
        Section(.app("View.DiagramFilterSection.Filter")) {
            SelectorEditor(title: .app("View.DiagramFilterSection.ShowOnly"), selector: nonOptionalFilter)
            presetControls
            AsyncOperationStatusView(identifierPrefix: "diagramFilter.presetSave", phase: presetSavePhase)
        }
        .task { await loadPresets() }
        .alert(.app("View.DiagramFilterSection.SavePreset"), isPresented: $showSaveAsPreset) {
            TextField(text: $presetName) {
                Text(.app("View.DiagramFilterSection.Name"))
            }
            .accessibilityIdentifier("diagram.filter.presetNameField")
            Button(.app("View.DiagramFilterSection.Save"), action: saveCurrentAsPreset)
                .accessibilityIdentifier("diagram.filter.presetSaveConfirmButton")
            Button(.app("View.DiagramFilterSection.Cancel"), role: .cancel) { presetName = "" }
        }
        .alert(
            .app("View.DiagramFilterSection.CouldNotSavePreset"),
            isPresented: Binding(get: { presetSaveError != nil }, set: { if !$0 { presetSaveError = nil } })
        ) {
            Button(.app("View.DiagramFilterSection.OK"), role: .cancel) { presetSaveError = nil }
        } message: {
            Text(verbatim: presetSaveError ?? "")
        }
        .confirmationDialog(
            .app("View.DiagramFilterSection.ConfirmDeletePreset \(presetPendingDelete?.name ?? "")"),
            isPresented: Binding(get: { presetPendingDelete != nil }, set: { if !$0 { presetPendingDelete = nil } }),
            presenting: presetPendingDelete
        ) { preset in
            Button(.app("View.DiagramFilterSection.Delete"), role: .destructive) {
                deletePreset(preset)
            }
            .accessibilityIdentifier("diagram.filter.presetDeleteConfirmButton")
            Button(.app("View.DiagramFilterSection.Cancel"), role: .cancel) { presetPendingDelete = nil }
        } message: { _ in
            Text(.app("View.DiagramFilterSection.ThisCannotBeUndone"))
        }
    }

    private var nonOptionalFilter: Binding<AcaiQuality.Selector> {
        Binding(
            get: { filter ?? AcaiQuality.Selector() },
            set: { newValue in filter = newValue == AcaiQuality.Selector() ? nil : newValue }
        )
    }

    // MARK: - Presets

    @ViewBuilder
    private var presetControls: some View {
        ForEach(presets.presets) { preset in
            presetRow(preset)
        }
        Button(.app("View.DiagramFilterSection.SaveAsPreset")) { showSaveAsPreset = true }
            .accessibilityIdentifier("diagram.filter.saveAsPresetButton")
    }

    /// Tapping a preset applies it. Renaming swaps the row for a `TextField`, matching the pattern
    /// the project sidebar uses for renaming a diagram; deleting always confirms, naming the preset.
    @ViewBuilder
    private func presetRow(_ preset: FilterPreset) -> some View {
        if renamingPresetID == preset.id {
            TextField(text: $renamingPresetText) {
                Text(.app("View.DiagramFilterSection.Name"))
            }
            .accessibilityIdentifier("diagram.filter.presetRenameField")
            .onSubmit { commitRename(preset) }
        } else {
            Button {
                filter = preset.selector
            } label: {
                Text(verbatim: preset.name)
            }
            .accessibilityIdentifier("diagram.filter.presetRow.\(preset.id.uuidString)")
            .contextMenu {
                Button {
                    renamingPresetText = preset.name
                    renamingPresetID = preset.id
                } label: {
                    Label(.app("View.DiagramFilterSection.Rename"), systemImage: "pencil")
                }
                .accessibilityIdentifier("diagram.filter.presetRow.\(preset.id.uuidString).rename")
                Button(role: .destructive) {
                    presetPendingDelete = preset
                } label: {
                    Label(.app("View.DiagramFilterSection.Delete"), systemImage: "trash")
                }
                .accessibilityIdentifier("diagram.filter.presetRow.\(preset.id.uuidString).contextDelete")
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    presetPendingDelete = preset
                } label: {
                    Label(.app("View.DiagramFilterSection.Delete"), systemImage: "trash")
                }
                .accessibilityIdentifier("diagram.filter.presetRow.\(preset.id.uuidString).swipeDelete")
            }
        }
    }

    private func loadPresets() async {
        let baseDir = model.store.baseDir
        let projectID = projectID
        presets = await Task.detached(priority: .userInitiated) {
            FilterPresetStore(baseDir: baseDir).load(projectID: projectID)
        }.value
    }

    private func saveCurrentAsPreset() {
        let trimmed = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        presetName = ""
        guard !trimmed.isEmpty else { return }
        var updated = presets
        updated.addPreset(name: trimmed, selector: filter)
        presets = updated
        persist(updated)
    }

    private func commitRename(_ preset: FilterPreset) {
        let trimmed = renamingPresetText.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingPresetID = nil
        guard !trimmed.isEmpty, trimmed != preset.name else { return }
        var updated = presets
        updated.rename(preset.id, to: trimmed)
        presets = updated
        persist(updated)
    }

    private func deletePreset(_ preset: FilterPreset) {
        var updated = presets
        updated.remove(preset.id)
        presets = updated
        persist(updated)
    }

    /// Saves off the main actor — call after `presets` already reflects the change locally, so the
    /// UI never waits on disk I/O to show a rename or delete.
    private func persist(_ list: FilterPresetList) {
        let baseDir = model.store.baseDir
        let projectID = projectID
        // A fresh `let` (not a `var`) so this Sendable value crosses the isolation boundary as an
        // immutable copy — same rebinding `FindingsView.toggleSuppressed` uses.
        let toSave = list
        presetSavePhase = .loading(.app("View.DiagramFilterSection.SavingPreset"))
        let previousSave = pendingPresetSave
        pendingPresetSave = Task {
            _ = await previousSave?.value
            do {
                try await Task.detached(priority: .userInitiated) {
                    try FilterPresetStore(baseDir: baseDir).save(toSave, projectID: projectID)
                }.value
                presetSavePhase = .loaded
            } catch {
                presetSaveError = error.localizedDescription
                presetSavePhase = .failed(error.localizedDescription)
            }
        }
    }
}
