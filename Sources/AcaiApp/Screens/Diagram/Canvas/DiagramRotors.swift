import SwiftUI
import AcaiRender

extension View {
    /// Every rotor is always declared: a conditional one would reset the identity of the canvas below it.
    func diagramRotors(_ plan: DiagramRotorPlan, in namespace: Namespace.ID) -> some View {
        accessibilityElement(children: .contain)
            .accessibilityLabel(Text(.app("View.DiagramRotors.Canvas")))
            // Behind the controls overlaid on the canvas, whose frames its own frame lies under.
            .accessibilitySortPriority(-1)
            .accessibilityRotor(Text(.app("View.DiagramRotors.Elements"))) {
                ForEach(plan.elements) { element in
                    AccessibilityRotorEntry(element.label, element.id, in: namespace)
                }
            }
            .accessibilityRotor(Text(.app("View.DiagramRotors.Connections"))) {
                ForEach(plan.connections) { connection in
                    AccessibilityRotorEntry(connection.label, connection.id, in: namespace)
                }
            }
            .accessibilityRotor(Text(.app("View.DiagramRotors.Changed"))) {
                ForEach(plan.changed) { element in
                    AccessibilityRotorEntry(element.label, element.id, in: namespace)
                }
            }
    }

    /// A container, so the box's label text takes the box's place in the reading order.
    func groupingBoxReadingOrder(id: String, in plan: DiagramRotorPlan) -> some View {
        accessibilityElement(children: .contain)
            .accessibilitySortPriority(plan.sortPriority(of: id))
    }

    /// Applied after `diagramNodeAccessibility`, so it lands on the element that modifier made.
    func diagramRotorMember(id: String, in plan: DiagramRotorPlan, namespace: Namespace.ID) -> some View {
        accessibilityRotorEntry(id: id, in: namespace)
            .accessibilitySortPriority(plan.sortPriority(of: id))
    }
}

extension DiagramRotorPlan {
    /// Labelled from the plan, so an edge layer doesn't describe the connection a second time.
    func edgeAccessibility(of id: String, identifier: String, namespace: Namespace.ID) -> EdgeAccessibility? {
        label(ofConnection: id).map { label in
            EdgeAccessibility(
                label: label, identifier: identifier, sortPriority: sortPriority(of: id),
                rotorEntry: EdgeAccessibility.RotorEntry(id: id, namespace: namespace)
            )
        }
    }
}

extension EdgeAccessibility {
    func rotorMember(id: String, in plan: DiagramRotorPlan, namespace: Namespace.ID) -> EdgeAccessibility {
        EdgeAccessibility(
            label: label, identifier: identifier, sortPriority: plan.sortPriority(of: id),
            rotorEntry: RotorEntry(id: id, namespace: namespace)
        )
    }
}
