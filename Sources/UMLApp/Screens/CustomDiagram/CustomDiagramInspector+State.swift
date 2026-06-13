import SwiftUI
import UMLDiagram

// MARK: - State Inspectors (states, transitions)
//
// The inspector sections for state-diagram elements: editing a transition edge (endpoints,
// event, guard, action) and a state node's UML flavour. Split from the main inspector file,
// which hosts the node/relationship sections.

extension CustomDiagramInspector {

    /// Inspector for a state-transition edge: endpoints plus the UML
    /// `event [guard] / action` label parts.
    func transitionSection(edge: CustomDiagram.Edge) -> some View {
        let stateNodes = viewModel.nodes.filter { viewModel.isStateNode($0.id) }
        return Section {
            Picker("From", selection: Binding(
                get: { edge.sourceNodeID },
                set: { viewModel.updateEdge(edge.id, sourceID: $0, targetID: edge.targetNodeID, kind: edge.kind) }
            )) {
                ForEach(stateNodes) { node in Text(stateDisplayName(node)).tag(node.id) }
            }

            Picker("To", selection: Binding(
                get: { edge.targetNodeID },
                set: { viewModel.updateEdge(edge.id, sourceID: edge.sourceNodeID, targetID: $0, kind: edge.kind) }
            )) {
                ForEach(stateNodes) { node in Text(stateDisplayName(node)).tag(node.id) }
            }

            TextField("Event", text: Binding(
                get: { edge.transition?.event ?? "" },
                set: { viewModel.updateTransitionEdge(edge.id, event: $0) }
            ))
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: .name)

            TextField("Guard condition", text: Binding(
                get: { edge.transition?.guardCondition ?? "" },
                set: { viewModel.updateTransitionEdge(edge.id, guardCondition: $0) }
            ))
            .textFieldStyle(.roundedBorder)

            TextField("Action", text: Binding(
                get: { edge.transition?.action ?? "" },
                set: { viewModel.updateTransitionEdge(edge.id, action: $0) }
            ))
            .textFieldStyle(.roundedBorder)
        } header: {
            Text("Transition").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    /// Inspector section for a state node's UML flavour.
    func stateKindSection(nodeID: String, kind: StateDiagram.State.Kind) -> some View {
        Section {
            Picker("State kind", selection: Binding(
                get: { kind },
                set: { viewModel.updateStateKind(nodeID, kind: $0) }
            )) {
                Text("State").tag(StateDiagram.State.Kind.normal)
                Text("Initial").tag(StateDiagram.State.Kind.initial)
                Text("Final").tag(StateDiagram.State.Kind.final)
                Text("Choice").tag(StateDiagram.State.Kind.choice)
            }
            .labelsHidden()
        } header: {
            Text("State Kind").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    /// Pseudo-states have empty names; fall back to their kind for picker rows.
    private func stateDisplayName(_ node: CustomDiagram.Node) -> String {
        if !node.name.isEmpty { return node.name }
        if case .state(let kind) = node.content {
            return "(\(kind.rawValue))"
        }
        return "?"
    }
}
