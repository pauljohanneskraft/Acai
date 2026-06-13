import SwiftUI
import UMLCore
import UMLDiagram

// MARK: - Catalog Sidebar

/// Sidebar panel listing available node kinds and relationship types
/// for the freeform diagram editor.
struct FreeformDiagramCatalog: View {
    @ObservedObject var viewModel: FreeformDiagramViewModel
    let canvasScale: CGFloat
    let canvasOffset: CGPoint
    let onInsertNode: (FreeformDiagramNodeKind, CGPoint) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Node Catalog")
                    .font(.headline)
                    .padding(.horizontal)

                nodeTypeCatalog

                Divider()
                    .padding(.horizontal)

                Text("Relationship Catalog")
                    .font(.headline)
                    .padding(.horizontal)

                relationshipCatalog

                Divider()
                    .padding(.horizontal)

                Text("Message Catalog")
                    .font(.headline)
                    .padding(.horizontal)

                messageCatalog

                Divider()
                    .padding(.horizontal)

                Text("Transition Catalog")
                    .font(.headline)
                    .padding(.horizontal)

                transitionCatalog
            }
            .padding(.vertical)
        }
    }

    // MARK: - Node Type Catalog

    private var nodeTypeCatalog: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(FreeformDiagramNodeKind.CatalogGroup.allCases, id: \.rawValue) { group in
                catalogSection(group.rawValue) {
                    ForEach(FreeformDiagramNodeKind.cases(in: group)) { kind in
                        catalogButton(kind: kind)
                    }
                }
            }
        }
    }

    private func catalogSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 2)
            content()
        }
    }

    private func catalogButton(kind: FreeformDiagramNodeKind) -> some View {
        Button {
            let centerX = (450 - canvasOffset.x) / canvasScale
            let centerY = (300 - canvasOffset.y) / canvasScale
            onInsertNode(kind, CGPoint(x: centerX, y: centerY))
        } label: {
            HStack {
                Image(systemName: kind.systemImage)
                    .frame(width: 20)
                Text(kind.displayName)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .onDrag {
            NSItemProvider(object: kind.id as NSString)
        }
    }

    // MARK: - Relationship Catalog

    private var relationshipCatalog: some View {
        VStack(spacing: 4) {
            relationshipButton(label: "Inheritance", kind: .inheritance)
            relationshipButton(label: "Conformance", kind: .conformance)
            relationshipButton(label: "Composition", kind: .composition)
            relationshipButton(label: "Aggregation", kind: .aggregation)
            relationshipButton(label: "Association", kind: .association)
            relationshipButton(label: "Dependency", kind: .dependency)
            relationshipButton(label: "Nesting", kind: .nesting)
            relationshipButton(label: "Extension", kind: .extension)
        }
    }

    private func relationshipButton(label: String, kind: Relationship.Kind) -> some View {
        Button {
            // Selection *order* determines direction: first selected → second selected.
            let selected = viewModel.selectionOrder
            if selected.count == 2 {
                viewModel.addEdge(from: selected[0], to: selected[1], kind: kind)
            }
        } label: {
            HStack {
                Image(systemName: "arrow.right")
                    .frame(width: 20)
                Text(label)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.selectedNodeIDs.count != 2)
    }

    // MARK: - Message Catalog (sequence diagrams)

    /// Buttons that append a message between the selected lifelines, at the end of the
    /// timeline. Direction is first-selected → second-selected; one selected lifeline makes a
    /// self-message. Order/kind/label are editable afterwards in the inspector.
    private var messageCatalog: some View {
        let lifelines = viewModel.orderedLifelineSelection
        let twoSelected = lifelines.count == 2
        let oneSelected = lifelines.count == 1
        return VStack(spacing: 4) {
            messageButton(label: "Message (sync)", icon: "arrow.right", kind: .synchronous,
                          enabled: twoSelected)
            messageButton(label: "Message (async)", icon: "arrow.right.to.line", kind: .asynchronous,
                          enabled: twoSelected)
            messageButton(label: "Return", icon: "arrowshape.turn.up.left", kind: .return,
                          enabled: twoSelected)
            messageButton(label: "Self-Message", icon: "arrow.uturn.down", kind: .synchronous,
                          enabled: oneSelected, isSelf: true)
            if !twoSelected && !oneSelected {
                Text("Select one or two lifelines (⌘-click) to add messages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - Transition Catalog (state diagrams)

    /// Button that connects the selected states with a transition. Direction is
    /// first-selected → second-selected; one selected state makes a self-loop.
    /// Event/guard/action are editable afterwards in the inspector.
    private var transitionCatalog: some View {
        let states = viewModel.orderedStateSelection
        let twoSelected = states.count == 2
        let oneSelected = states.count == 1
        return VStack(spacing: 4) {
            Button {
                if twoSelected {
                    viewModel.addTransition(from: states[0], to: states[1])
                } else if oneSelected, let only = states.first {
                    viewModel.addTransition(from: only, to: only)
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.right")
                        .frame(width: 20)
                    Text(oneSelected ? "Self-Transition" : "Transition")
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .disabled(!twoSelected && !oneSelected)
            if !twoSelected && !oneSelected {
                Text("Select one or two states (⌘-click) to add a transition.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
        }
    }

    private func messageButton(
        label: String,
        icon: String,
        kind: SequenceDiagram.Message.Kind,
        enabled: Bool,
        isSelf: Bool = false
    ) -> some View {
        Button {
            let lifelines = viewModel.orderedLifelineSelection
            if isSelf, let only = lifelines.first {
                viewModel.addMessage(from: only, to: only, kind: kind)
            } else if lifelines.count == 2 {
                viewModel.addMessage(from: lifelines[0], to: lifelines[1], kind: kind)
            }
        } label: {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(label)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
