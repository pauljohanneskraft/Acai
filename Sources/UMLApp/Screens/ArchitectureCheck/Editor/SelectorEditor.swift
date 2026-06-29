import SwiftUI
import UMLConformance
import UMLCore

/// Form controls for a `Selector` — the shared "which types/modules" predicate used by every rule
/// kind. Each facet is optional and AND-combined; an empty field leaves that facet unset.
struct SelectorEditor: View {
    let title: String
    @Binding var selector: UMLConformance.Selector

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            TextField("Module glob (e.g. ui.*)", text: $selector.module.orEmpty)
            TextField("Type glob (e.g. *Repository)", text: $selector.typeGlob.orEmpty)
            TextField("Stereotype (e.g. entity)", text: $selector.stereotype.orEmpty)
            TextField("Annotation (e.g. Entity)", text: $selector.annotation.orEmpty)
            Picker("Minimum access", selection: $selector.minimumAccess) {
                Text("Any").tag(AccessLevel?.none)
                ForEach(AccessLevel.allCases, id: \.self) { level in
                    Text(level.rawValue).tag(AccessLevel?.some(level))
                }
            }
        }
        .textFieldStyle(.roundedBorder)
    }
}
