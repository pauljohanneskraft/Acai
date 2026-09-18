import SwiftUI
import AcaiCore
import AcaiRender

struct FocusSection: View {
    @Binding var configuration: ClassDiagramConfiguration
    let typeNames: [String]

    var body: some View {
        Section(.app("View.FocusSection.Focus")) {
            Toggle(.app("View.FocusSection.FocusClass"), isOn: focusEnabled)
                .accessibilityIdentifier("diagram.focus.toggle")

            if configuration.focus != nil {
                Picker(.app("View.FocusSection.RootType"), selection: rootType) {
                    ForEach(typeNames, id: \.self) { Text(verbatim: $0).tag($0) }
                }
                .accessibilityIdentifier("diagram.focus.rootTypePicker")

                Toggle(.app("View.FocusSection.LimitDepth"), isOn: depthLimited)
                    .accessibilityIdentifier("diagram.focus.depthToggle")
                if configuration.focus?.maxDepth != nil {
                    Stepper(
                        .app("View.FocusSection.Depth \(configuration.focus?.maxDepth ?? 1)"),
                        value: depthValue, in: 1...20
                    )
                }

                Picker(.app("View.FocusSection.Direction"), selection: direction) {
                    Text(.app("View.FocusSection.Dependencies")).tag(FocusConfiguration.Direction.dependencies)
                    Text(.app("View.FocusSection.Dependents")).tag(FocusConfiguration.Direction.dependents)
                    Text(.app("View.FocusSection.Both")).tag(FocusConfiguration.Direction.both)
                }
                .accessibilityIdentifier("diagram.focus.directionPicker")

                DisclosureGroup {
                    ForEach(Relationship.Kind.allCases, id: \.self) { kind in
                        Toggle(kind.rawValue.capitalized, isOn: kindBinding(kind))
                    }
                } label: {
                    Text(.app("View.FocusSection.RelationshipKinds"))
                }

                Toggle(.app("View.FocusSection.IncludeInterconnections"), isOn: interconnections)
                    .accessibilityIdentifier("diagram.focus.interconnectionsToggle")
            }
        }
    }

    private var focusEnabled: Binding<Bool> {
        Binding(
            get: { configuration.focus != nil },
            set: { configuration.focus = $0 ? FocusConfiguration(rootTypeName: typeNames.first ?? "") : nil }
        )
    }

    private var rootType: Binding<String> {
        Binding(
            get: { configuration.focus?.rootTypeName ?? "" },
            set: { configuration.focus?.rootTypeName = $0 }
        )
    }

    private var depthLimited: Binding<Bool> {
        Binding(
            get: { configuration.focus?.maxDepth != nil },
            set: { configuration.focus?.maxDepth = $0 ? 3 : nil }
        )
    }

    private var depthValue: Binding<Int> {
        Binding(
            get: { configuration.focus?.maxDepth ?? 3 },
            set: { configuration.focus?.maxDepth = $0 }
        )
    }

    private var direction: Binding<FocusConfiguration.Direction> {
        Binding(
            get: { configuration.focus?.direction ?? .dependencies },
            set: { configuration.focus?.direction = $0 }
        )
    }

    private func kindBinding(_ kind: Relationship.Kind) -> Binding<Bool> {
        Binding(
            get: { configuration.focus?.includedRelationshipKinds.contains(kind) ?? false },
            set: { include in
                if include {
                    configuration.focus?.includedRelationshipKinds.insert(kind)
                } else {
                    configuration.focus?.includedRelationshipKinds.remove(kind)
                }
            }
        )
    }

    private var interconnections: Binding<Bool> {
        Binding(
            get: { configuration.focus?.includeInterconnections ?? true },
            set: { configuration.focus?.includeInterconnections = $0 }
        )
    }
}
