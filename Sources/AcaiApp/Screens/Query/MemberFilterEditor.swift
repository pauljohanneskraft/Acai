import SwiftUI
import AcaiQuality
import AcaiCore

/// Form controls for a `MemberFilter` — the member-level companion to `SelectorEditor`'s type-level
/// `Selector`. Each facet is optional and AND-combined; an empty/off field leaves that facet unset.
struct MemberFilterEditor: View {
    let title: LocalizedStringResource
    @Binding var filter: MemberFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localized: title).font(.caption.bold()).foregroundStyle(.secondary)
            Picker(.app("View.MemberFilterEditor.Kind"), selection: $filter.kind) {
                Text(.app("View.MemberFilterEditor.AnyKind")).tag(MemberKind?.none)
                ForEach(MemberKind.allCases, id: \.self) { kind in
                    Text(verbatim: kind.rawValue).tag(MemberKind?.some(kind))
                }
            }
            .accessibilityIdentifier("query.memberFilter.kindPicker")
            TextField(text: $filter.minParameters.asText) {
                Text(.app("View.MemberFilterEditor.MinParametersEG"))
            }
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("query.memberFilter.minParametersField")
            Toggle(.app("View.MemberFilterEditor.MutablePublicStateOnly"), isOn: $filter.isPublicVar.orFalse)
                .accessibilityIdentifier("query.memberFilter.mutablePublicStateToggle")
            Toggle(.app("View.MemberFilterEditor.OverridesOnly"), isOn: $filter.isOverride.orFalse)
                .accessibilityIdentifier("query.memberFilter.overridesToggle")
        }
    }
}
