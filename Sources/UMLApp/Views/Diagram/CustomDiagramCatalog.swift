import SwiftUI
import UMLCore

// MARK: - Catalog Sidebar

/// Sidebar panel listing available node kinds and relationship types
/// for the custom diagram editor.
struct CustomDiagramCatalog: View {
    @ObservedObject var viewModel: CustomDiagramEditorViewModel
    let canvasScale: CGFloat
    let canvasOffset: CGPoint
    let onInsertNode: (DiagramElementKind, CGPoint) -> Void

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
            }
            .padding(.vertical)
        }
    }

    // MARK: - Node Type Catalog

    private var nodeTypeCatalog: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(DiagramElementKind.CatalogGroup.allCases, id: \.rawValue) { group in
                catalogSection(group.rawValue) {
                    ForEach(DiagramElementKind.catalogItems(in: group)) { kind in
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

    private func catalogButton(kind: DiagramElementKind) -> some View {
        Button {
            let centerX = (canvasOffset.x * -1 + 450) / canvasScale
            let centerY = (canvasOffset.y * -1 + 300) / canvasScale
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
            // If exactly two nodes are selected, create an edge between them.
            let selected = Array(viewModel.selectedNodeIDs)
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
}
