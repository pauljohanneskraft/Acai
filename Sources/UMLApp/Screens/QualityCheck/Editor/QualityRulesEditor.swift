import SwiftUI
import UMLQuality

/// The form for authoring a `QualityRules` set in the UI — one section per rule kind. Bound
/// directly to a working copy held by the editor sheet; serialized to YAML on save.
struct QualityRulesEditor: View {
    @Binding var rules: QualityRules

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Include generated types", isOn: $rules.includeGeneratedTypes)
                .font(.headline)
            Text("When off (the default), machine-generated types are excluded from metrics, code "
                + "smells and cycles — matching the CLI (`--include-generated`) and MCP defaults.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var cyclesEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Detect dependency cycles", isOn: cyclesEnabled)
                .font(.headline)
            if let binding = Binding($rules.cycles) {
                Picker("Scope", selection: binding.scope) {
                    ForEach(CycleRule.Scope.allCases, id: \.self) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        .padding(.vertical, 4)
    }

    private var cyclesEnabled: Binding<Bool> {
        Binding(
            get: { rules.cycles != nil },
            set: { rules.cycles = $0 ? CycleRule(scope: .modules) : nil }
        )
    }
}
