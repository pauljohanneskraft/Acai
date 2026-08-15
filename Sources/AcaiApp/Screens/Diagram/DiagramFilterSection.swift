import SwiftUI
import AcaiCore
import AcaiQuality

/// A "Filter" `Form` section shared by every diagram type's Settings tab: the unmodified
/// `SelectorEditor` (the same selector vocabulary `AcaiQuality`'s rules already use, instead of a
/// second, diagram-specific filter), a "Save as Quality Rule" reverse action, and named,
/// project-wide filter presets (save the current filter / apply a saved one).
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

    var body: some View {
        Section("Filter") {
            SelectorEditor(title: "Show only", selector: nonOptionalFilter)
            saveAsQualityRuleButton
            presetControls
        }
        .task { await loadPresets() }
        .alert("Save as Preset", isPresented: $showSaveAsPreset) {
            TextField("Name", text: $presetName)
                .accessibilityIdentifier("diagram.filter.presetNameField")
            Button("Save", action: saveCurrentAsPreset)
                .accessibilityIdentifier("diagram.filter.presetSaveConfirmButton")
            Button("Cancel", role: .cancel) { presetName = "" }
        }
        .sheet(isPresented: $showQualityRulesEditor) {
            QualityCheckEditorSheet(codebaseID: codebaseID, artifact: artifact)
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
        Button("Save as Quality Rule") {
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
            Picker("Apply Preset", selection: presetSelection) {
                Text("Choose…").tag(UUID?.none)
                ForEach(presets.presets) { preset in
                    Text(preset.name).tag(UUID?.some(preset.id))
                }
            }
            .accessibilityIdentifier("diagram.filter.presetPicker")
        }
        Button("Save as Preset…") { showSaveAsPreset = true }
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
        Task {
            try? await Task.detached(priority: .userInitiated) {
                try FilterPresetStore(baseDir: baseDir).save(toSave, projectID: projectID)
            }.value
        }
    }
}
