import SwiftUI
import UMLCore

// MARK: - Inspector Sidebar

/// Inspector panel for the custom diagram editor, showing details of the
/// currently-selected node, edge, or multi-selection.
struct CustomDiagramInspector: View {
    @ObservedObject var viewModel: CustomDiagramViewModel

    @State private var newPropertyText: String = ""
    @State private var newMethodText: String = ""

    var body: some View {
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
                set: { viewModel.updateNode(node.id, name: $0, kind: node.content.kind) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.headline)
        } header: {
            Text("Name").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    private func nodeKindSection(node: CustomDiagram.Node) -> some View {
        Section {
            Picker("Kind", selection: Binding(
                get: { node.content.kind },
                set: { viewModel.updateNode(node.id, name: node.name, kind: $0) }
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
            } header: {
                Text("Note Text").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func nodeRelationshipsSection(node: CustomDiagram.Node) -> some View {
        let relatedEdges = viewModel.edges.filter { $0.sourceNodeID == node.id || $0.targetNodeID == node.id }
        if !relatedEdges.isEmpty {
            Section {
                ForEach(relatedEdges) { edge in
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
                Text("Relationships (\(relatedEdges.count))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Member Sections

    private func propertiesSection(nodeID: UUID, content: CustomDiagram.Node.TypeContent) -> some View {
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

    private func methodsSection(nodeID: UUID, content: CustomDiagram.Node.TypeContent) -> some View {
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

    // MARK: - Edge Inspector

    private func edgeInspector(edge: CustomDiagram.Edge) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                edgePickersSection(edge: edge)
                edgeSummary(edge: edge)
                Button(role: .destructive) {
                    viewModel.removeEdge(edge.id)
                    viewModel.selectedEdgeID = nil
                } label: {
                    Label("Delete Relationship", systemImage: "trash")
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
                for id in viewModel.selectedNodeIDs {
                    viewModel.removeNode(id)
                }
            } label: {
                Label("Delete Selected", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding()
        }
    }
}
