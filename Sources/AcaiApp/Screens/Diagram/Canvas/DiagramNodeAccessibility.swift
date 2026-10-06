import SwiftUI

extension View {
    /// One VoiceOver element per canvas node: activating it selects, "Show Details" opens the inspector.
    /// `identifier` is re-applied last because `children: .ignore` drops the node view's own.
    func diagramNodeAccessibility(
        _ description: DiagramElementDescription,
        identifier: String,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onShowDetails: @escaping () -> Void
    ) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: description.label))
            .accessibilityValue(Text(verbatim: description.value))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { onSelect() }
            .accessibilityAction(named: Text(.app("View.DiagramNodeAccessibility.ShowDetails"))) { onShowDetails() }
            .accessibilityIdentifier(identifier)
    }
}
