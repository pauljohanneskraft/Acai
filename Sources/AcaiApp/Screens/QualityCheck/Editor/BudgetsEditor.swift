import SwiftUI
import AcaiQuality

/// Editor for metric budgets: a selector-matched metric must stay within optional `min`/`max` bounds.
struct BudgetsEditor: View {
    @Binding var budgets: [MetricBudget]

    var body: some View {
        RuleSection(
            title: .app("View.BudgetsEditor.MetricBudgets"),
            total: budgets.count,
            onAdd: { budgets.append(MetricBudget(metric: .distance)) },
            content: {
                ForEach(budgets.indices, id: \.self) { index in
                    row(index)
                }
            })
    }

    private func row(_ index: Int) -> some View {
        RuleCard(onRemove: { budgets.remove(at: index) }, content: {
            Picker(.app("View.BudgetsEditor.Metric"), selection: $budgets[index].metric) {
                ForEach(MetricBudget.Metric.allCases, id: \.self) { metric in
                    Text(verbatim: metric.rawValue).tag(metric)
                }
            }
            HStack(spacing: 8) {
                Text(.app("View.BudgetsEditor.Min")).font(.caption).foregroundStyle(.secondary)
                TextField(text: $budgets[index].min.asText) {
                    Text(.app("View.BudgetsEditor.None"))
                }
                Text(.app("View.BudgetsEditor.Max")).font(.caption).foregroundStyle(.secondary)
                TextField(text: $budgets[index].max.asText) {
                    Text(.app("View.BudgetsEditor.None"))
                }
            }
            .textFieldStyle(.roundedBorder)
            SelectorEditor(title: .app("View.BudgetsEditor.AppliesToOptional"), selector: $budgets[index].target)
            TextField(text: $budgets[index].message.orEmpty) {
                Text(.app("View.BudgetsEditor.CustomMessageOptional"))
            }
            .textFieldStyle(.roundedBorder)
        })
    }
}
