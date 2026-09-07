import SwiftUI
import AcaiCore
import AcaiDiagram

// MARK: - Sequence Inspectors (messages, fragments)

extension FreeformDiagramInspector {

    func messageSection(edge: FreeformDiagram.Edge) -> some View {
        Section {
            Picker(.app("View.FreeformDiagramInspector.From"), selection: Binding(
                get: { edge.sourceNodeID },
                set: { viewModel.updateEdge(edge.id, sourceID: $0, targetID: edge.targetNodeID, kind: edge.kind) }
            )) {
                ForEach(viewModel.sequence.lifelineNodes) { node in Text(verbatim: node.name).tag(node.id) }
            }

            Picker(.app("View.FreeformDiagramInspector.To"), selection: Binding(
                get: { edge.targetNodeID },
                set: { viewModel.updateEdge(edge.id, sourceID: edge.sourceNodeID, targetID: $0, kind: edge.kind) }
            )) {
                ForEach(viewModel.sequence.lifelineNodes) { node in Text(verbatim: node.name).tag(node.id) }
            }

            TextField(text: Binding(
                get: { edge.label ?? "" },
                set: { viewModel.sequence.updateMessageEdge(edge.id, label: $0) }
            )) {
                Text(.app("View.FreeformDiagramInspector.Label"))
            }
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: .name)

            Picker(.app("View.FreeformDiagramInspector.KindPicker"), selection: Binding(
                get: { edge.messageKind ?? .synchronous },
                set: { viewModel.sequence.updateMessageEdge(edge.id, messageKind: $0) }
            )) {
                Text(.app("View.FreeformDiagramInspector.Synchronous")).tag(SequenceDiagram.Message.Kind.synchronous)
                Text(.app("View.FreeformDiagramInspector.Asynchronous")).tag(SequenceDiagram.Message.Kind.asynchronous)
                Text(.app("View.FreeformDiagramInspector.Return")).tag(SequenceDiagram.Message.Kind.return)
                Text(.app("View.FreeformDiagramInspector.Create")).tag(SequenceDiagram.Message.Kind.create)
                Text(.app("View.FreeformDiagramInspector.Destroy")).tag(SequenceDiagram.Message.Kind.destroy)
            }

            Stepper(value: Binding(
                get: { edge.messageOrder ?? 0 },
                set: { viewModel.sequence.updateMessageEdge(edge.id, messageOrder: $0) }
            )) {
                Text(.app("View.FreeformDiagramInspector.Order \(edge.messageOrder ?? 0)"))
            }
        } header: {
            Text(.app("View.FreeformDiagramInspector.Message"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    /// Each operand's `firstOrder`/`lastOrder` span is inclusive.
    func fragmentSection(nodeID: String, content: FreeformDiagram.Node.FragmentContent) -> some View {
        Section {
            Picker(.app("View.FreeformDiagramInspector.Operator"), selection: Binding(
                get: { content.kind },
                set: { viewModel.sequence.updateFragment(nodeID, kind: $0) }
            )) {
                ForEach(SequenceDiagram.Fragment.Kind.allCases, id: \.self) { kind in
                    Text(verbatim: kind.rawValue).tag(kind)
                }
            }

            ForEach(Array(content.operands.enumerated()), id: \.offset) { index, operand in
                fragmentOperandRow(nodeID: nodeID, content: content, index: index, operand: operand)
            }

            Button {
                var operands = content.operands
                let nextOrder = (operands.last?.lastOrder ?? 0) + 1
                operands.append(.init(firstOrder: nextOrder, lastOrder: nextOrder))
                viewModel.sequence.updateFragment(nodeID, operands: operands)
            } label: {
                Label(.app("View.FreeformDiagramInspector.AddOperand"), systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        } header: {
            Text(.app("View.FreeformDiagramInspector.Fragment"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func fragmentOperandRow(
        nodeID: String,
        content: FreeformDiagram.Node.FragmentContent,
        index: Int,
        operand: SequenceDiagram.Fragment.Operand
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField(text: Binding(
                    get: { operand.guardLabel ?? "" },
                    set: { newValue in
                        var operands = content.operands
                        operands[index].guardLabel = newValue.isEmpty ? nil : newValue
                        viewModel.sequence.updateFragment(nodeID, operands: operands,
                                                 coalescingKey: "fragmentGuard-\(nodeID)-\(index)")
                    }
                )) {
                    Text(.app("View.FreeformDiagramInspector.GuardEGCart"))
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                if content.operands.count > 1 {
                    Button(role: .destructive) {
                        var operands = content.operands
                        operands.remove(at: index)
                        viewModel.sequence.updateFragment(nodeID, operands: operands)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            operandRangeRow(nodeID: nodeID, content: content, index: index, operand: operand)
        }
        .padding(.vertical, 2)
    }

    /// The two steppers bounding a fragment operand — labelled "From"/"To", since two bare numbers
    /// side by side say nothing about which end is which, to the eye or to VoiceOver.
    private func operandRangeRow(
        nodeID: String,
        content: FreeformDiagram.Node.FragmentContent,
        index: Int,
        operand: SequenceDiagram.Fragment.Operand
    ) -> some View {
        HStack {
            Stepper(value: Binding(
                get: { operand.firstOrder },
                set: { newValue in
                    var operands = content.operands
                    operands[index].firstOrder = newValue
                    viewModel.sequence.updateFragment(nodeID, operands: operands)
                }
            )) {
                Text(.app("View.FreeformDiagramInspector.OperandFrom \(operand.firstOrder)"))
                    .font(.caption.monospaced())
            }
            Stepper(value: Binding(
                get: { operand.lastOrder },
                set: { newValue in
                    var operands = content.operands
                    operands[index].lastOrder = newValue
                    viewModel.sequence.updateFragment(nodeID, operands: operands)
                }
            )) {
                Text(.app("View.FreeformDiagramInspector.OperandTo \(operand.lastOrder)"))
                    .font(.caption.monospaced())
            }
        }
    }
}
