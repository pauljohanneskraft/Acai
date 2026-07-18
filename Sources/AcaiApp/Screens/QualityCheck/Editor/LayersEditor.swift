import SwiftUI
import AcaiQuality

/// Editor for the ordered-layer rule: dependencies may only flow downward through the listed layers
/// (top → bottom). The whole rule is optional, gated behind an enable toggle.
struct LayersEditor: View {
    @Binding var rule: LayerRule?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Enforce layering", isOn: enabled)
                .font(.headline)
            if let binding = Binding($rule) {
                enabledBody(binding)
            }
        }
        .padding(.vertical, 4)
    }

    private var enabled: Binding<Bool> {
        Binding(
            get: { rule != nil },
            set: { rule = $0 ? LayerRule(layers: []) : nil }
        )
    }

    @ViewBuilder
    private func enabledBody(_ rule: Binding<LayerRule>) -> some View {
        Text("Layers from top (highest level) to bottom.").font(.caption).foregroundStyle(.secondary)
        ForEach(rule.layers.indices, id: \.self) { index in
            RuleCard(onRemove: { rule.wrappedValue.layers.remove(at: index) }, content: {
                TextField("Layer name (e.g. UI)", text: rule.layers[index].name)
                    .textFieldStyle(.roundedBorder)
                SelectorEditor(title: "Matches", selector: rule.layers[index].selector)
            })
        }
        HStack {
            Button {
                rule.wrappedValue.layers.append(LayerRule.Layer(name: "", selector: AcaiQuality.Selector()))
            } label: {
                Label("Add layer", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            Spacer()
            Toggle("Allow skipping layers", isOn: rule.allowSkip)
        }
    }
}
