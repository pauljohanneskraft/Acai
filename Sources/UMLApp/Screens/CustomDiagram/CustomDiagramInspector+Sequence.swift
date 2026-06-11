import SwiftUI
import UMLCore
import UMLDiagram

// MARK: - Sequence Inspectors (messages, fragments)
//
// The inspector sections for sequence-diagram elements: editing a message edge (endpoints,
// label, kind, time order) and a combined fragment (operator + operands). Split from the main
// inspector file, which hosts the node/relationship sections.

extension CustomDiagramInspector {

    /// Inspector for a sequence message edge: endpoints, label, kind and time order.
    func messageSection(edge: CustomDiagram.Edge) -> some View {
        Section {
            Picker("From", selection: Binding(
                get: { edge.sourceNodeID },
                set: { viewModel.updateEdge(edge.id, sourceID: $0, targetID: edge.targetNodeID, kind: edge.kind) }
            )) {
                ForEach(viewModel.lifelineNodes) { node in Text(node.name).tag(node.id) }
            }

            Picker("To", selection: Binding(
                get: { edge.targetNodeID },
                set: { viewModel.updateEdge(edge.id, sourceID: edge.sourceNodeID, targetID: $0, kind: edge.kind) }
            )) {
                ForEach(viewModel.lifelineNodes) { node in Text(node.name).tag(node.id) }
            }

            TextField("Label", text: Binding(
                get: { edge.label ?? "" },
                set: { viewModel.updateMessageEdge(edge.id, label: $0) }
            ))
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: .name)

            Picker("Kind", selection: Binding(
                get: { edge.messageKind ?? .synchronous },
                set: { viewModel.updateMessageEdge(edge.id, messageKind: $0) }
            )) {
                Text("Synchronous").tag(SequenceDiagram.Message.Kind.synchronous)
                Text("Asynchronous").tag(SequenceDiagram.Message.Kind.asynchronous)
                Text("Return").tag(SequenceDiagram.Message.Kind.return)
                Text("Create").tag(SequenceDiagram.Message.Kind.create)
                Text("Destroy").tag(SequenceDiagram.Message.Kind.destroy)
            }

            Stepper(value: Binding(
                get: { edge.messageOrder ?? 0 },
                set: { viewModel.updateMessageEdge(edge.id, messageOrder: $0) }
            )) {
                Text("Order: \(edge.messageOrder ?? 0)")
            }
        } header: {
            Text("Message").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    /// Inspector for a combined fragment: operator kind plus its operands (guard condition and
    /// the inclusive message-order span each operand covers).
    func fragmentSection(nodeID: String, content: CustomDiagram.Node.FragmentContent) -> some View {
        Section {
            Picker("Operator", selection: Binding(
                get: { content.kind },
                set: { viewModel.updateFragment(nodeID, kind: $0) }
            )) {
                ForEach(SequenceDiagram.Fragment.Kind.allCases, id: \.self) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }

            ForEach(Array(content.operands.enumerated()), id: \.offset) { index, operand in
                fragmentOperandRow(nodeID: nodeID, content: content, index: index, operand: operand)
            }

            Button {
                var operands = content.operands
                let nextOrder = (operands.last?.lastOrder ?? 0) + 1
                operands.append(.init(firstOrder: nextOrder, lastOrder: nextOrder))
                viewModel.updateFragment(nodeID, operands: operands)
            } label: {
                Label("Add Operand", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Fragment").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    private func fragmentOperandRow(
        nodeID: String,
        content: CustomDiagram.Node.FragmentContent,
        index: Int,
        operand: SequenceDiagram.Fragment.Operand
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Guard (e.g. cart != empty)", text: Binding(
                    get: { operand.guardLabel ?? "" },
                    set: { newValue in
                        var operands = content.operands
                        operands[index].guardLabel = newValue.isEmpty ? nil : newValue
                        viewModel.updateFragment(nodeID, operands: operands,
                                                 coalescingKey: "fragmentGuard-\(nodeID)-\(index)")
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                if content.operands.count > 1 {
                    Button(role: .destructive) {
                        var operands = content.operands
                        operands.remove(at: index)
                        viewModel.updateFragment(nodeID, operands: operands)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                Stepper(value: Binding(
                    get: { operand.firstOrder },
                    set: { newValue in
                        var operands = content.operands
                        operands[index].firstOrder = newValue
                        viewModel.updateFragment(nodeID, operands: operands)
                    }
                )) {
                    Text("From: \(operand.firstOrder)").font(.caption.monospaced())
                }
                Stepper(value: Binding(
                    get: { operand.lastOrder },
                    set: { newValue in
                        var operands = content.operands
                        operands[index].lastOrder = newValue
                        viewModel.updateFragment(nodeID, operands: operands)
                    }
                )) {
                    Text("To: \(operand.lastOrder)").font(.caption.monospaced())
                }
            }
        }
        .padding(.vertical, 2)
    }
}
