import SwiftUI
import UMLQuality

/// Editor for metric budgets: a selector-matched metric must stay within optional `min`/`max` bounds.
struct BudgetsEditor: View {
    @Binding var budgets: [MetricBudget]

    var body: some View {
        RuleSection(
            title: "Metric budgets",
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
            Picker("Metric", selection: $budgets[index].metric) {
                ForEach(MetricBudget.Metric.allCases, id: \.self) { metric in
                    Text(metric.rawValue).tag(metric)
                }
            }
            HStack(spacing: 8) {
                Text("Min").font(.caption).foregroundStyle(.secondary)
                TextField("none", text: $budgets[index].min.asText)
                Text("Max").font(.caption).foregroundStyle(.secondary)
                TextField("none", text: $budgets[index].max.asText)
            }
            .textFieldStyle(.roundedBorder)
            SelectorEditor(title: "Applies to (optional)", selector: $budgets[index].target)
            TextField("Custom message (optional)", text: $budgets[index].message.orEmpty)
                .textFieldStyle(.roundedBorder)
        })
    }
}
