import SwiftUI

extension View {
    /// The rotors a VoiceOver user turns to reach one canvas element directly instead of sweeping the
    /// whole canvas. Declared once on the canvas; each element joins them through
    /// `diagramRotorMember(id:in:namespace:)`.
    ///
    /// Both rotors are always declared. Making the changed-elements rotor appear only while a
    /// comparison is active would change the canvas's view type as the comparison comes and goes,
    /// resetting the identity of everything drawn below it.
    func diagramRotors(_ plan: DiagramRotorPlan, in namespace: Namespace.ID) -> some View {
        accessibilityRotor(Text(.app("View.DiagramRotors.Elements"))) {
            ForEach(plan.elements) { element in
                AccessibilityRotorEntry(element.label, element.id, in: namespace)
            }
        }
        .accessibilityRotor(Text(.app("View.DiagramRotors.Changed"))) {
            ForEach(plan.changed) { element in
                AccessibilityRotorEntry(element.label, element.id, in: namespace)
            }
        }
    }

    /// Puts one element in the canvas's rotors, at its place in the reading order. Applied after
    /// `diagramNodeAccessibility`, so it lands on the element that modifier made.
    func diagramRotorMember(id: String, in plan: DiagramRotorPlan, namespace: Namespace.ID) -> some View {
        accessibilityRotorEntry(id: id, in: namespace)
            .accessibilitySortPriority(plan.sortPriority(of: id))
    }
}
