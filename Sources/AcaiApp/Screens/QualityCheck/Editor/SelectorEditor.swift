import SwiftUI
import AcaiQuality
import AcaiCore

/// Form controls for a `Selector` — the shared "which types/modules" predicate used by every rule
/// kind. Each facet is optional and AND-combined; an empty field leaves that facet unset.
struct SelectorEditor: View {
    let title: LocalizedStringResource
    @Binding var selector: AcaiQuality.Selector
    var identifierPrefix: String?

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingXS) {
            Text(localized: title).font(.caption.bold()).foregroundStyle(.secondary)
            TextField(text: $selector.module.orEmpty) {
                Text(.app("View.SelectorEditor.ModuleGlobEG"))
            }
            .accessibilityIdentifier(identifier("module"))
            TextField(text: $selector.typeGlob.orEmpty) {
                Text(.app("View.SelectorEditor.TypeGlobEG"))
            }
            .accessibilityIdentifier(identifier("typeGlob"))
            TextField(text: $selector.stereotype.orEmpty) {
                Text(.app("View.SelectorEditor.StereotypeEGEntity"))
            }
            .accessibilityIdentifier(identifier("stereotype"))
            TextField(text: $selector.annotation.orEmpty) {
                Text(.app("View.SelectorEditor.AnnotationEGEntity"))
            }
            .accessibilityIdentifier(identifier("annotation"))
            Picker(.app("View.SelectorEditor.MinimumAccess"), selection: $selector.minimumAccess) {
                Text(.app("View.SelectorEditor.AnyAccessLevel")).tag(AccessLevel?.none)
                ForEach(AccessLevel.allCases, id: \.self) { level in
                    Text(verbatim: level.rawValue).tag(AccessLevel?.some(level))
                }
            }
            Picker(.app("View.SelectorEditor.Kind"), selection: $selector.kind) {
                Text(.app("View.SelectorEditor.AnyAccessLevel")).tag(TypeKind?.none)
                ForEach(TypeKind.allCases, id: \.self) { kind in
                    Text(verbatim: kind.rawValue).tag(TypeKind?.some(kind))
                }
            }
            TextField(text: $selector.minMembers.asText) {
                Text(.app("View.SelectorEditor.MinMembersEG"))
            }
            .accessibilityIdentifier(identifier("minMembers"))
            TextField(text: $selector.minNesting.asText) {
                Text(.app("View.SelectorEditor.MinNestingEG"))
            }
            .accessibilityIdentifier(identifier("minNesting"))
        }
        .textFieldStyle(.roundedBorder)
    }

    private func identifier(_ facet: String) -> String {
        identifierPrefix.map { "\($0).\(facet)" } ?? ""
    }
}
