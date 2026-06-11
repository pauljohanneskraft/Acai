import SwiftUI
import UMLCore
import UMLDiagram

// MARK: - Inspector Sidebar

/// Inspector panel for the custom diagram editor, showing details of the
/// currently-selected node, edge, or multi-selection.
struct CustomDiagramInspector: View {
    @ObservedObject var viewModel: CustomDiagramViewModel
    /// Mirrors whether any text field here is focused, so the parent can suspend its ⌘Z/⇧⌘Z
    /// shortcuts and let the focused field handle native text undo.
    @Binding var isEditingText: Bool

    @State private var newPropertyText: String = ""
    @State private var newMethodText: String = ""
    /// Internal (not private) so the sequence-inspector extension file can focus fields too.
    @FocusState var focusedField: Field?

    /// Text fields that, while focused, should own ⌘Z.
    enum Field: Hashable { case name, note, newProperty, newMethod }

    var body: some View {
        Group {
            if let edgeID = viewModel.selectedEdgeID,
               let edge = viewModel.edges.first(where: { $0.id == edgeID }) {
                edgeInspector(edge: edge)
            } else if viewModel.selectedNodeIDs.count == 1,
                      let nodeID = viewModel.selectedNodeIDs.first,
                      let node = viewModel.nodes.first(where: { $0.id == nodeID }) {
                nodeInspector(node: node)
            } else if viewModel.selectedNodeIDs.count > 1 {
                multiNodeInspector
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "cursorarrow.click")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("Select a node or relationship to inspect")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: focusedField) { _, newValue in
            isEditingText = (newValue != nil)
        }
        .onDisappear { isEditingText = false }
    }

    // MARK: - Node Inspector

    private func nodeInspector(node: CustomDiagram.Node) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                nodeNameSection(node: node)
                nodeKindSection(node: node)
                nodePositionSection(node: node)
                nodeContentSections(node: node)
                nodeRelationshipsSection(node: node)
                Button(role: .destructive) {
                    viewModel.removeNode(node.id)
                } label: {
                    Label("Delete Node", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
    }

    private func nodeNameSection(node: CustomDiagram.Node) -> some View {
        Section {
            TextField("Name", text: Binding(
                get: { node.name },
                set: { viewModel.updateNodeName(node.id, name: $0) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.headline)
            .focused($focusedField, equals: .name)
        } header: {
            Text("Name").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    private func nodeKindSection(node: CustomDiagram.Node) -> some View {
        Section {
            Picker("Kind", selection: Binding(
                get: { node.content.kind },
                set: { viewModel.updateNode(node.id, kind: $0) }
            )) {
                ForEach(CustomDiagramNodeKind.CatalogGroup.allCases, id: \.rawValue) { group in
                    Section(group.rawValue) {
                        ForEach(CustomDiagramNodeKind.cases(in: group)) { elementKind in
                            Text(elementKind.displayName).tag(elementKind)
                        }
                    }
                }
            }
            .labelsHidden()
        } header: {
            Text("Kind").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    private func nodePositionSection(node: CustomDiagram.Node) -> some View {
        Section {
            HStack {
                Text("X: \(Int(node.positionX))").font(.caption.monospaced())
                Spacer()
                Text("Y: \(Int(node.positionY))").font(.caption.monospaced())
            }
            let size = viewModel.nodeSize(node.id)
            HStack {
                Text("W: \(Int(size.width))").font(.caption.monospaced())
                Spacer()
                Text("H: \(Int(size.height))").font(.caption.monospaced())
            }
        } header: {
            Text("Position & Size").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func nodeContentSections(node: CustomDiagram.Node) -> some View {
        if case .type(let content) = node.content {
            propertiesSection(nodeID: node.id, content: content)
            methodsSection(nodeID: node.id, content: content)
        }
        if case .note(let text) = node.content {
            Section {
                TextEditor(text: Binding(
                    get: { text },
                    set: { viewModel.updateNoteText(node.id, text: $0) }
                ))
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 80)
                .border(Color.secondary.opacity(0.3))
                .focused($focusedField, equals: .note)
            } header: {
                Text("Note Text").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        if case .lifeline(let kind) = node.content {
            Section {
                Picker("Role", selection: Binding(
                    get: { kind },
                    set: { viewModel.updateLifelineKind(node.id, kind: $0) }
                )) {
                    ForEach(SequenceDiagram.Participant.Kind.allCases, id: \.self) { role in
                        Text(role.rawValue.capitalized).tag(role)
                    }
                }
                .labelsHidden()
            } header: {
                Text("Participant Role").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        if case .fragment(let content) = node.content {
            fragmentSection(nodeID: node.id, content: content)
        }
    }

    @ViewBuilder
    private func nodeRelationshipsSection(node: CustomDiagram.Node) -> some View {
        // Sequence messages are listed separately from structural relationships, using the same
        // predicate the canvas renders by (`isMessageEdge`), so the two can never disagree.
        let relatedEdges = viewModel.edges.filter { $0.sourceNodeID == node.id || $0.targetNodeID == node.id }
        let messages = relatedEdges
            .filter { viewModel.isMessageEdge($0) }
            .sorted { ($0.messageOrder ?? 0) < ($1.messageOrder ?? 0) }
        let relationships = relatedEdges.filter { !viewModel.isMessageEdge($0) }

        if !messages.isEmpty {
            messagesListSection(node: node, messages: messages)
        }
        if !relationships.isEmpty {
            relationshipsListSection(node: node, relationships: relationships)
        }
    }

    private func messagesListSection(node: CustomDiagram.Node, messages: [CustomDiagram.Edge]) -> some View {
        Section {
            ForEach(messages) { edge in
                HStack {
                    let outgoing = edge.sourceNodeID == node.id
                    let otherID = outgoing ? edge.targetNodeID : edge.sourceNodeID
                    let otherName = viewModel.nodes.first(where: { $0.id == otherID })?.name ?? "?"
                    Text("\(edge.messageOrder ?? 0).")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(edge.label ?? (edge.messageKind == .return ? "(return)" : "(message)"))
                        .font(.caption.monospaced())
                    Spacer()
                    Text(outgoing ? "→ \(otherName)" : "← \(otherName)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectedEdgeID = edge.id
                }
            }
        } header: {
            Text("Messages (\(messages.count))")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func relationshipsListSection(
        node: CustomDiagram.Node,
        relationships: [CustomDiagram.Edge]
    ) -> some View {
        Section {
            ForEach(relationships) { edge in
                HStack {
                    Text(edge.kind.rawValue)
                        .font(.caption)
                    Spacer()
                    let otherID = edge.sourceNodeID == node.id ? edge.targetNodeID : edge.sourceNodeID
                    let otherName = viewModel.nodes.first(where: { $0.id == otherID })?.name ?? "?"
                    Text(otherName)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectedEdgeID = edge.id
                }
            }
        } header: {
            Text("Relationships (\(relationships.count))")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Member Sections

    private func propertiesSection(nodeID: String, content: CustomDiagram.Node.TypeContent) -> some View {
        Section {
            ForEach(content.properties) { prop in
                HStack {
                    Text(prop.displayString)
                        .font(.system(size: 12, design: .monospaced))
                    Spacer()
                    Button(role: .destructive) {
                        viewModel.removeProperty(from: nodeID, memberID: prop.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("e.g. name: String", text: $newPropertyText)
                    .font(.system(size: 12, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .newProperty)
                Button {
                    viewModel.addPropertyFromText(to: nodeID, text: newPropertyText)
                    newPropertyText = ""
                } label: {
                    Image(systemName: "plus.circle")
                }
                .disabled(newPropertyText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Properties").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    private func methodsSection(nodeID: String, content: CustomDiagram.Node.TypeContent) -> some View {
        Section {
            ForEach(content.methods) { method in
                HStack {
                    Text(method.displayString)
                        .font(.system(size: 12, design: .monospaced))
                    Spacer()
                    Button(role: .destructive) {
                        viewModel.removeMethod(from: nodeID, memberID: method.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("e.g. doWork(input: Int): String", text: $newMethodText)
                    .font(.system(size: 12, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .newMethod)
                Button {
                    viewModel.addMethodFromText(to: nodeID, text: newMethodText)
                    newMethodText = ""
                } label: {
                    Image(systemName: "plus.circle")
                }
                .disabled(newMethodText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Methods").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Edge & Multi-Node Inspectors

extension CustomDiagramInspector {

    private func edgeInspector(edge: CustomDiagram.Edge) -> some View {
        // Same predicate the canvas renders by, so the editor always matches what's drawn.
        let isMessage = viewModel.isMessageEdge(edge)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isMessage {
                    messageSection(edge: edge)
                } else {
                    edgePickersSection(edge: edge)
                }
                edgeSummary(edge: edge)
                Button(role: .destructive) {
                    viewModel.removeEdge(edge.id)
                    viewModel.selectedEdgeID = nil
                } label: {
                    Label(isMessage ? "Delete Message" : "Delete Relationship",
                          systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
    }

    private func edgePickersSection(edge: CustomDiagram.Edge) -> some View {
        Section {
            Picker("Source", selection: Binding(
                get: { edge.sourceNodeID },
                set: { newSource in
                    viewModel.updateEdge(edge.id, sourceID: newSource,
                                         targetID: edge.targetNodeID, kind: edge.kind)
                }
            )) {
                ForEach(viewModel.nodes) { node in Text(node.name).tag(node.id) }
            }

            Picker("Target", selection: Binding(
                get: { edge.targetNodeID },
                set: { newTarget in
                    viewModel.updateEdge(edge.id, sourceID: edge.sourceNodeID,
                                         targetID: newTarget, kind: edge.kind)
                }
            )) {
                ForEach(viewModel.nodes) { node in Text(node.name).tag(node.id) }
            }

            Picker("Kind", selection: Binding(
                get: { edge.kind },
                set: { newKind in
                    viewModel.updateEdge(edge.id, sourceID: edge.sourceNodeID,
                                         targetID: edge.targetNodeID, kind: newKind)
                }
            )) {
                Text("Inheritance").tag(Relationship.Kind.inheritance)
                Text("Conformance").tag(Relationship.Kind.conformance)
                Text("Composition").tag(Relationship.Kind.composition)
                Text("Aggregation").tag(Relationship.Kind.aggregation)
                Text("Association").tag(Relationship.Kind.association)
                Text("Dependency").tag(Relationship.Kind.dependency)
            }
        } header: {
            Text("Relationship").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    private func edgeSummary(edge: CustomDiagram.Edge) -> some View {
        let sourceName = viewModel.nodes.first(where: { $0.id == edge.sourceNodeID })?.name ?? "?"
        let targetName = viewModel.nodes.first(where: { $0.id == edge.targetNodeID })?.name ?? "?"
        return Text("\(sourceName) → \(targetName)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Multi-Node Inspector

    private var multiNodeInspector: some View {
        VStack(spacing: 12) {
            Text("\(viewModel.selectedNodeIDs.count) nodes selected")
                .font(.headline)

            List {
                ForEach(Array(viewModel.selectedNodeIDs), id: \.self) { nodeID in
                    if let node = viewModel.nodes.first(where: { $0.id == nodeID }) {
                        HStack {
                            Image(systemName: node.content.kind.systemImage)
                            Text(node.name)
                        }
                    }
                }
            }
            .listStyle(.inset)

            Button(role: .destructive) {
                viewModel.deleteSelection()
            } label: {
                Label("Delete Selected", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding()
        }
    }
}
