import SwiftUI
import AcaiCore
import AcaiQuality

/// A "Filter" `Form` section shared by every diagram type's Settings tab: the unmodified
/// `SelectorEditor` (the same selector vocabulary `AcaiQuality`'s rules already use, instead of a
/// second, diagram-specific filter), a "Save as Quality Rule" reverse action, and named,
/// project-wide filter presets.
struct DiagramFilterSection: View {
    @Binding var filter: AcaiQuality.Selector?
    let codebaseID: UUID
    let projectID: UUID
    let artifact: CodeArtifact

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var presets = FilterPresetList()
    @State private var showSaveAsPreset = false
    @State private var presetName = ""
    @State private var showQualityRulesEditor = false
    @State private var presetSavePhase: AsyncOperationPhase = .idle
    @State private var presetSaveError: String?

    var body: some View {
        Section(.app("View.DiagramFilterSection.Filter")) {
            SelectorEditor(title: .app("View.DiagramFilterSection.ShowOnly"), selector: nonOptionalFilter)
            saveAsQualityRuleButton
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
        .sheet(isPresented: $showQualityRulesEditor) {
            QualityCheckEditorSheet(codebaseID: codebaseID, artifact: artifact)
        }
        .alert(
            .app("View.DiagramFilterSection.CouldNotSavePreset"),
            isPresented: Binding(get: { presetSaveError != nil }, set: { if !$0 { presetSaveError = nil } })
        ) {
            Button(.app("View.DiagramFilterSection.OK"), role: .cancel) { presetSaveError = nil }
        } message: {
            Text(verbatim: presetSaveError ?? "")
        }
    }

    private var nonOptionalFilter: Binding<AcaiQuality.Selector> {
        Binding(
            get: { filter ?? AcaiQuality.Selector() },
            set: { newValue in filter = newValue == AcaiQuality.Selector() ? nil : newValue }
        )
    }

    private var isFilterEmpty: Bool {
        (filter ?? AcaiQuality.Selector()) == AcaiQuality.Selector()
    }

    private var ruleAction: QualityRuleFromSelector {
        QualityRuleFromSelector(model: model, codebaseID: codebaseID)
    }

    private var saveAsQualityRuleButton: some View {
        Button(.app("View.DiagramFilterSection.SaveQualityRule")) {
            ruleAction.appendRule(for: filter ?? AcaiQuality.Selector())
            showQualityRulesEditor = true
        }
        .disabled(isFilterEmpty || !ruleAction.isAvailable)
        .help(
            ruleAction.isAvailable
                ? "Append this filter as an editable rule to the codebase's quality check"
                : "This codebase's quality check points at an external YAML file — edit it there instead"
        )
        .accessibilityIdentifier("diagram.filter.saveAsQualityRuleButton")
    }

    // MARK: - Presets

    @ViewBuilder
    private var presetControls: some View {
        if !presets.presets.isEmpty {
            Picker(.app("View.DiagramFilterSection.ApplyPreset"), selection: presetSelection) {
                Text(.app("View.DiagramFilterSection.Choose")).tag(UUID?.none)
                ForEach(presets.presets) { preset in
                    Text(verbatim: preset.name).tag(UUID?.some(preset.id))
                }
            }
            .accessibilityIdentifier("diagram.filter.presetPicker")
        }
        Button(.app("View.DiagramFilterSection.SaveAsPreset")) { showSaveAsPreset = true }
            .accessibilityIdentifier("diagram.filter.saveAsPresetButton")
    }

    /// Always reads back `nil` ("Choose…") after applying, so re-picking the same preset re-applies
    /// it instead of the picker looking permanently "stuck" on a stale selection.
    private var presetSelection: Binding<UUID?> {
        Binding(
            get: { nil },
            set: { newID in
                guard let newID, let preset = presets.presets.first(where: { $0.id == newID }) else { return }
                filter = preset.selector
            }
        )
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
        updated.presets.append(FilterPreset(name: trimmed, selector: filter))
        presets = updated
        let baseDir = model.store.baseDir
        let projectID = projectID
        // A fresh `let` (not the `var` mutated above) so this Sendable value crosses the isolation
        // boundary as an immutable copy — same rebinding `FindingsView.toggleSuppressed` uses.
        let toSave = updated
        presetSavePhase = .loading(.app("View.DiagramFilterSection.SavingPreset"))
        Task {
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
