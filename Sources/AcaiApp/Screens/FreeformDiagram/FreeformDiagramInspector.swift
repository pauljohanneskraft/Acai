import SwiftUI
import AcaiCore
import AcaiDiagram

// MARK: - Inspector Sidebar

struct FreeformDiagramInspector: View {
    @ObservedObject var viewModel: FreeformDiagramViewModel
    /// Mirrors whether any text field here is focused, so the parent can suspend its ⌘Z/⇧⌘Z
    /// shortcuts and let the focused field handle native text undo.
    @Binding var isEditingText: Bool

    // Not `private`: `FreeformDiagramInspector+Members.swift` (a same-type extension in another
    // file) reads/resets these for the inline add-property/add-method rows.
    @State var newPropertyName: String = ""
    @State var newPropertyType: String = ""
    @State var newPropertyAccessLevel: AccessLevel = .internal
    @State var newPropertyIsStatic = false
    @State var newPropertyIsAbstract = false
    @State var newMethodName: String = ""
    @State var newMethodReturnType: String = ""
    @State var newMethodParameters: [FreeformDiagram.Node.Parameter] = []
    @State var newMethodAccessLevel: AccessLevel = .internal
    @State var newMethodIsStatic = false
    @State var newMethodIsAbstract = false
    @State var memberSheet: MemberSheet?
    /// Internal (not private) so the sequence-inspector extension file can focus fields too.
    @FocusState var focusedField: Field?

    /// Text fields that, while focused, should own ⌘Z.
    enum Field: Hashable { case name, note, newProperty, newMethod }

    /// Not `private`: referenced by `FreeformDiagramInspector+Members.swift` too.
    enum MemberSheet: Identifiable {
        case addProperty(nodeID: String)
        case editProperty(nodeID: String, memberID: UUID)
        case addMethod(nodeID: String)
        case editMethod(nodeID: String, memberID: UUID)

        var id: String {
            switch self {
            case .addProperty(let nodeID):
                "addProperty-\(nodeID)"
            case .editProperty(let nodeID, let memberID):
                "editProperty-\(nodeID)-\(memberID)"
            case .addMethod(let nodeID):
                "addMethod-\(nodeID)"
            case .editMethod(let nodeID, let memberID):
                "editMethod-\(nodeID)-\(memberID)"
            }
        }
    }

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
                    Text(.app("View.FreeformDiagramInspector.SelectNodeRelationshipInspect"))
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
        .sheet(item: $memberSheet) { sheet in
            memberSheetContent(sheet)
        }
    }

}

// MARK: - Node Inspector

extension FreeformDiagramInspector {

    private func nodeInspector(node: FreeformDiagram.Node) -> some View {
        Form {
            nodeNameSection(node: node)
            nodeKindSection(node: node)
            nodePositionSection(node: node)
            nodeContentSections(node: node)
            nodeRelationshipsSection(node: node)
            Section {
                Button(role: .destructive) {
                    viewModel.removeNode(node.id)
                } label: {
                    Label(.app("View.FreeformDiagramInspector.DeleteNode"), systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func nodeNameSection(node: FreeformDiagram.Node) -> some View {
        Section {
            TextField(text: Binding(
                get: { node.name },
                set: { viewModel.members.updateNodeName(node.id, name: $0) }
            )) {
                Text(.app("View.FreeformDiagramInspector.Name"))
            }
            .textFieldStyle(.roundedBorder)
            .font(.headline)
            .focused($focusedField, equals: .name)
        } header: {
            Text(.app("View.FreeformDiagramInspector.Name"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func nodeKindSection(node: FreeformDiagram.Node) -> some View {
        Section {
            Picker(.app("View.FreeformDiagramInspector.Kind"), selection: Binding(
                get: { node.content.kind },
                set: { viewModel.updateNode(node.id, kind: $0) }
            )) {
                ForEach(FreeformDiagramNodeKind.CatalogGroup.allCases, id: \.rawValue) { group in
                    Section(group.rawValue) {
                        ForEach(FreeformDiagramNodeKind.cases(in: group)) { elementKind in
                            Text(verbatim: elementKind.displayName).tag(elementKind)
                        }
                    }
                }
            }
            .labelsHidden()
        } header: {
            Text(.app("View.FreeformDiagramInspector.Kind"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    /// Coalescing keys for runs of consecutive keystrokes in one numeric field, so typing a
    /// multi-digit value undoes as a single step (mirrors `TypeMemberEditor`'s own text fields).
    private enum PositionField: Hashable {
        case x(String), y(String), width(String), height(String)
    }

    private func nodePositionSection(node: FreeformDiagram.Node) -> some View {
        Section {
            HStack {
                TextField(.app("View.FreeformDiagramInspector.X"), value: positionXBinding(node: node), format: .number)
                    .accessibilityIdentifier("inspector.positionXField")
                TextField(.app("View.FreeformDiagramInspector.Y"), value: positionYBinding(node: node), format: .number)
                    .accessibilityIdentifier("inspector.positionYField")
            }
            HStack {
                TextField(.app("View.FreeformDiagramInspector.W"), value: widthBinding(node: node), format: .number)
                    .accessibilityIdentifier("inspector.widthField")
                TextField(.app("View.FreeformDiagramInspector.H"), value: heightBinding(node: node), format: .number)
                    .accessibilityIdentifier("inspector.heightField")
            }
        } header: {
            Text(.app("View.FreeformDiagramInspector.PositionSize"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func positionXBinding(node: FreeformDiagram.Node) -> Binding<Double> {
        Binding(
            get: { node.positionX },
            set: { newValue in
                viewModel.recordUndo(coalescingKey: PositionField.x(node.id))
                viewModel.moveNode(node.id, to: CGPoint(x: CGFloat(newValue), y: CGFloat(node.positionY)))
                viewModel.save()
            }
        )
    }

    private func positionYBinding(node: FreeformDiagram.Node) -> Binding<Double> {
        Binding(
            get: { node.positionY },
            set: { newValue in
                viewModel.recordUndo(coalescingKey: PositionField.y(node.id))
                viewModel.moveNode(node.id, to: CGPoint(x: CGFloat(node.positionX), y: CGFloat(newValue)))
                viewModel.save()
            }
        )
    }

    /// Width/height editing applies to every node kind, not just resizable containers: rendering
    /// (`FreeformDiagramView+Canvas.swift`'s `nodeContent`) already honors an explicit size for
    /// any kind once set, so a typed value here works the same way a container drag-resize does.
    private func widthBinding(node: FreeformDiagram.Node) -> Binding<Double> {
        Binding(
            get: { viewModel.nodeSize(node.id).width },
            set: { newValue in
                let currentHeight = viewModel.nodeSize(node.id).height
                viewModel.recordUndo(coalescingKey: PositionField.width(node.id))
                viewModel.resizeNode(node.id, width: CGFloat(newValue), height: currentHeight)
                viewModel.save()
            }
        )
    }

    private func heightBinding(node: FreeformDiagram.Node) -> Binding<Double> {
        Binding(
            get: { viewModel.nodeSize(node.id).height },
            set: { newValue in
                let currentWidth = viewModel.nodeSize(node.id).width
                viewModel.recordUndo(coalescingKey: PositionField.height(node.id))
                viewModel.resizeNode(node.id, width: currentWidth, height: CGFloat(newValue))
                viewModel.save()
            }
        )
    }

    @ViewBuilder
    private func nodeContentSections(node: FreeformDiagram.Node) -> some View {
        if case .type(let content) = node.content {
            propertiesSection(nodeID: node.id, content: content)
            methodsSection(nodeID: node.id, content: content)
        }
        if case .note(let text) = node.content {
            Section {
                TextEditor(text: Binding(
                    get: { text },
                    set: { viewModel.members.updateNoteText(node.id, text: $0) }
                ))
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 80)
                .border(Color.secondary.opacity(0.3))
                .focused($focusedField, equals: .note)
            } header: {
                Text(.app("View.FreeformDiagramInspector.NoteText"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        if case .lifeline(let kind) = node.content {
            Section {
                Picker(.app("View.FreeformDiagramInspector.Role"), selection: Binding(
                    get: { kind },
                    set: { viewModel.sequence.updateLifelineKind(node.id, kind: $0) }
                )) {
                    ForEach(SequenceDiagram.Participant.Kind.allCases, id: \.self) { role in
                        Text(verbatim: role.rawValue.capitalized).tag(role)
                    }
                }
                .labelsHidden()
            } header: {
                Text(.app("View.FreeformDiagramInspector.ParticipantRole"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        if case .fragment(let content) = node.content {
            fragmentSection(nodeID: node.id, content: content)
        }
        if case .state(let kind) = node.content {
            stateKindSection(nodeID: node.id, kind: kind)
        }
    }

    @ViewBuilder
    private func nodeRelationshipsSection(node: FreeformDiagram.Node) -> some View {
        // Sequence messages are listed separately from structural relationships, using the same
        // predicate the canvas renders by (`isMessageEdge`), so the two can never disagree.
        let relatedEdges = viewModel.edges.filter { $0.sourceNodeID == node.id || $0.targetNodeID == node.id }
        let messages = relatedEdges
            .filter { viewModel.sequence.isMessageEdge($0) }
            .sorted { ($0.messageOrder ?? 0) < ($1.messageOrder ?? 0) }
        let relationships = relatedEdges.filter { !viewModel.sequence.isMessageEdge($0) }

        if !messages.isEmpty {
            messagesListSection(node: node, messages: messages)
        }
        if !relationships.isEmpty {
            relationshipsListSection(node: node, relationships: relationships)
        }
    }

    private func messagesListSection(node: FreeformDiagram.Node, messages: [FreeformDiagram.Edge]) -> some View {
        Section {
            ForEach(messages) { edge in
                HStack {
                    let outgoing = edge.sourceNodeID == node.id
                    let otherID = outgoing ? edge.targetNodeID : edge.sourceNodeID
                    let otherName = viewModel.nodes.first(where: { $0.id == otherID })?.name ?? "?"
                    Text(verbatim: "\(edge.messageOrder ?? 0).")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    (edge.label.map { Text(verbatim: $0) } ?? Text(localized: placeholderLabel(for: edge)))
                        .font(.caption.monospaced())
                    Spacer()
                    Text(verbatim: outgoing ? "→ \(otherName)" : "← \(otherName)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectedEdgeID = edge.id
                }
            }
        } header: {
            Text(.app("View.FreeformDiagramInspector.Messages \(messages.count)"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func placeholderLabel(for edge: FreeformDiagram.Edge) -> LocalizedStringResource {
        edge.messageKind == .return
            ? .app("View.FreeformDiagramInspector.UnlabelledReturn")
            : .app("View.FreeformDiagramInspector.UnlabelledMessage")
    }

    private func relationshipsListSection(
        node: FreeformDiagram.Node,
        relationships: [FreeformDiagram.Edge]
    ) -> some View {
        Section {
            ForEach(relationships) { edge in
                HStack {
                    Text(verbatim: edge.kind.rawValue)
                        .font(.caption)
                    Spacer()
                    let otherID = edge.sourceNodeID == node.id ? edge.targetNodeID : edge.sourceNodeID
                    let otherName = viewModel.nodes.first(where: { $0.id == otherID })?.name ?? "?"
                    Text(verbatim: otherName)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectedEdgeID = edge.id
                }
            }
        } header: {
            Text(.app("View.FreeformDiagramInspector.Relationships \(relationships.count)"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

}

// MARK: - Edge & Multi-Node Inspectors

extension FreeformDiagramInspector {

    private func edgeInspector(edge: FreeformDiagram.Edge) -> some View {
        // Same predicates the canvas renders by, so the editor always matches what's drawn.
        let isMessage = viewModel.sequence.isMessageEdge(edge)
        let isTransition = edge.transition != nil
        let deleteTitle = isMessage ? "Delete Message"
            : isTransition ? "Delete Transition" : "Delete Relationship"
        return Form {
            if isMessage {
                messageSection(edge: edge)
            } else if isTransition {
                transitionSection(edge: edge)
            } else {
                edgePickersSection(edge: edge)
            }
            Section {
                edgeSummary(edge: edge)
            }
            Section {
                Button(role: .destructive) {
                    viewModel.removeEdge(edge.id)
                    viewModel.selectedEdgeID = nil
                } label: {
                    Label(deleteTitle, systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func edgePickersSection(edge: FreeformDiagram.Edge) -> some View {
        Section {
            Picker(.app("View.FreeformDiagramInspector.Source"), selection: Binding(
                get: { edge.sourceNodeID },
                set: { newSource in
                    viewModel.updateEdge(edge.id, sourceID: newSource,
                                         targetID: edge.targetNodeID, kind: edge.kind)
                }
            )) {
                ForEach(viewModel.nodes) { node in Text(verbatim: node.name).tag(node.id) }
            }

            Picker(.app("View.FreeformDiagramInspector.Target"), selection: Binding(
                get: { edge.targetNodeID },
                set: { newTarget in
                    viewModel.updateEdge(edge.id, sourceID: edge.sourceNodeID,
                                         targetID: newTarget, kind: edge.kind)
                }
            )) {
                ForEach(viewModel.nodes) { node in Text(verbatim: node.name).tag(node.id) }
            }

            Picker(.app("View.FreeformDiagramInspector.KindPicker"), selection: Binding(
                get: { edge.kind },
                set: { newKind in
                    viewModel.updateEdge(edge.id, sourceID: edge.sourceNodeID,
                                         targetID: edge.targetNodeID, kind: newKind)
                }
            )) {
                Text(.app("View.FreeformDiagramInspector.Inheritance")).tag(Relationship.Kind.inheritance)
                Text(.app("View.FreeformDiagramInspector.Conformance")).tag(Relationship.Kind.conformance)
                Text(.app("View.FreeformDiagramInspector.Composition")).tag(Relationship.Kind.composition)
                Text(.app("View.FreeformDiagramInspector.Aggregation")).tag(Relationship.Kind.aggregation)
                Text(.app("View.FreeformDiagramInspector.Association")).tag(Relationship.Kind.association)
                Text(.app("View.FreeformDiagramInspector.Dependency")).tag(Relationship.Kind.dependency)
            }
        } header: {
            Text(.app("View.FreeformDiagramInspector.Relationship"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func edgeSummary(edge: FreeformDiagram.Edge) -> some View {
        let sourceName = viewModel.nodes.first(where: { $0.id == edge.sourceNodeID })?.name ?? "?"
        let targetName = viewModel.nodes.first(where: { $0.id == edge.targetNodeID })?.name ?? "?"
        return Text(.app("View.FreeformDiagramInspector.EdgeSummary \(sourceName) \(targetName)"))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Multi-Node Inspector

    @ViewBuilder
    private var multiNodeInspector: some View {
        Form {
            Section {
                ForEach(Array(viewModel.selectedNodeIDs), id: \.self) { nodeID in
                    if let node = viewModel.nodes.first(where: { $0.id == nodeID }) {
                        Label(node.name, systemImage: node.content.kind.systemImage)
                    }
                }
            } header: {
                Text(.app("View.FreeformDiagramInspector.NodesSelected \(viewModel.selectedNodeIDs.count)"))
            }
            Section {
                Button(role: .destructive) {
                    viewModel.deleteSelection()
                } label: {
                    Label(.app("View.FreeformDiagramInspector.DeleteSelected"), systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
