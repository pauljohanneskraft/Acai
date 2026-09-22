import SwiftUI
import AcaiQuality

/// The form for authoring a `QualityRules` set in the UI — one section per rule kind. Bound
/// directly to a working copy held by the editor sheet; serialized to YAML on save.
struct QualityRulesEditor: View {
    @Binding var rules: QualityRules

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            scopeEditor
            Divider()
            ForbiddenRulesEditor(rules: $rules.forbidden)
            Divider()
            cyclesEditor
            Divider()
            BudgetsEditor(budgets: $rules.budgets)
            Divider()
            LayersEditor(rule: $rules.layers)
            Divider()
            ContractsEditor(contracts: $rules.contracts)
        }
    }

    @ViewBuilder
    private var scopeEditor: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Toggle(.app("View.QualityRulesEditor.IncludeGeneratedTypes"), isOn: $rules.includeGeneratedTypes)
                .font(.headline)
            Text(.app("View.QualityRulesEditor.WhenOffDefaultMachine"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, Spacing.xs)
    }

    @ViewBuilder
    private var cyclesEditor: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Toggle(.app("View.QualityRulesEditor.DetectDependencyCycles"), isOn: cyclesEnabled)
                .font(.headline)
            if let binding = Binding($rules.cycles) {
                Picker(.app("View.QualityRulesEditor.Scope"), selection: binding.scope) {
                    ForEach(CycleRule.Scope.allCases, id: \.self) { scope in
                        Text(verbatim: scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private var cyclesEnabled: Binding<Bool> {
        Binding(
            get: { rules.cycles != nil },
            set: { rules.cycles = $0 ? CycleRule(scope: .modules) : nil }
        )
    }
}
