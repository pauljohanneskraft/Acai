import SwiftUI
import UMLCore
import UMLDiagram
import UMLRender
import UniformTypeIdentifiers

/// Movement-only view for a generated package (module-dependency) diagram. Derives the diagram
/// from the artifact and lets the user drag module nodes, on the shared canvas layer
/// (`PannableCanvas`, drag gesture, undo/redo) like the state view. Modules render as UML package
/// shapes (the same `ContainerNodeView` the freeform editor uses) tinted by their distance from
/// the main sequence; dependencies are dashed arrows whose thickness encodes their weight. All
/// numeric coupling metrics live in the inspector sidebar, never on the canvas.
struct PackageDiagramView: View {
    let diagram: GeneratedDiagram
    let artifact: CodeArtifact
    let codebase: Codebase

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @StateObject private var viewModel: PackageDiagramViewModel

    @State private var canvasScale: CGFloat
    @State private var canvasOffset: CGPoint
    @State private var dragStartPositions: [String: CGPoint] = [:]
    @State private var activeDragCanvasLocation: CGPoint?
    @State private var canvasAutoPanController = EdgeAutoPanController()
    @State private var showSidebar = true

    init(
        diagram: GeneratedDiagram, artifact: CodeArtifact, codebase: Codebase,
        comparisonArtifact: CodeArtifact? = nil
    ) {
        self.diagram = diagram
        self.artifact = artifact
        self.codebase = codebase
        self._viewModel = StateObject(wrappedValue: PackageDiagramViewModel(
            artifact: artifact,
            restoredPositions: diagram.nodePositions.mapValues(\.cgPoint),
            comparisonArtifact: comparisonArtifact
        ))
        self._canvasScale = State(initialValue: CGFloat(diagram.canvasScale))
        self._canvasOffset = State(initialValue: CGPoint(x: diagram.canvasOffsetX, y: diagram.canvasOffsetY))
    }

    var body: some View {
        HSplitView {
            canvasContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showSidebar {
                PackageDiagramInspector(
                    diagram: viewModel.diagram,
                    selectedNodeIDs: viewModel.selectedNodeIDs
                ).frame(minWidth: 240, idealWidth: 300, maxWidth: 380)
            }
        }
        .toolbar { toolbarContent }
        .diagramCanvasLifecycle(
            title: diagram.name, model: viewModel, onSave: savePositions, onCenter: centerDiagram
        )
    }

    // MARK: - Canvas

    private var canvasContent: some View {
        PannableCanvas(
            model: viewModel,
            scale: $canvasScale,
            offset: $canvasOffset,
            activeDragCanvasLocation: activeDragCanvasLocation,
            autoPanController: canvasAutoPanController
        ) {
            let layout = viewModel.layout
            ZStack(alignment: .topLeading) {
                packageEdges(layout)
                ForEach(layout.nodes) { node in
                    moduleNode(node)
                }
            }
        }
    }

    private func packageEdges(_ layout: PackageLayoutModel) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.edges) { edge in
                if let sourceRect = layout.frame(for: edge.from),
                   let targetRect = layout.frame(for: edge.to) {
                    RelationshipEdgeView(
                        kind: .dependency,
                        sourceRect: sourceRect,
                        targetRect: targetRect,
                        lineWidthScale: Self.lineWidthScale(forWeight: edge.weight),
                        strokeColor: viewModel.edgeDeltaColor(from: edge.from, to: edge.to)
                    )
                }
            }
        }
    }

    /// A coloured delta outline overlaid on a node, or nothing when the node is unchanged.
    @ViewBuilder
    private func deltaBorder(_ color: Color?) -> some View {
        if let color {
            RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 3)
        }
    }

    private func moduleNode(_ node: PackageLayoutModel.NodeFrame) -> some View {
        ContainerNodeView(
            name: node.node.name,
            stereotype: "package",
            style: .package,
            isSelected: viewModel.selectedNodeIDs.contains(node.id),
            size: node.rect.size,
            fillColor: Color(hex: node.node.zoneColorHex)
        )
        .frame(width: node.rect.width, height: node.rect.height)
        .overlay(deltaBorder(viewModel.nodeDeltaColor(id: node.id)))
        .position(x: node.rect.midX, y: node.rect.midY)
        .diagramNodeInteraction(
            id: node.id,
            model: viewModel,
            dragStartPositions: $dragStartPositions,
            activeDragCanvasLocation: $activeDragCanvasLocation,
            onCommit: savePositions
        )
    }

    /// Maps a dependency's weight to a line-width multiplier, clamped so the heaviest edges stay legible.
    private static func lineWidthScale(forWeight weight: Int) -> CGFloat {
        min(1 + CGFloat(weight - 1) * 0.35, 3)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            UndoRedoToolbarButtons(model: viewModel, onChange: savePositions)

            Button {
                centerDiagram()
            } label: {
                Label("Fit to View", systemImage: "rectangle.dashed")
            }
            Button {
                let layoutPositions = Dictionary(
                    viewModel.layout.nodes.map { ($0.id, CGPoint(x: $0.rect.midX, y: $0.rect.midY)) },
                    uniquingKeysWith: { first, _ in first }
                )
                model.saveAsFreeformDiagram(
                    id: diagram.id,
                    positions: layoutPositions,
                    scale: canvasScale,
                    offset: canvasOffset
                )
            } label: {
                Label("Save as Freeform", systemImage: "document.on.document")
            }
            Button {
                exportImage()
            } label: {
                Label("Export Image", systemImage: "photo")
            }
            Button {
                showSidebar.toggle()
            } label: {
                Label("Sidebar", systemImage: "sidebar.trailing")
            }
        }
    }

    private func exportImage() {
        model.exportImage(named: diagram.name, using: viewModel)
    }

    // MARK: - Persistence & layout

    private func savePositions() {
        model.diagrams.updatePositions(
            diagramID: diagram.id,
            positions: viewModel.positionOverrides,
            scale: canvasScale,
            offset: canvasOffset
        )
    }

    private func centerDiagram() {
        guard let fit = FitToView(
            nodeIDs: viewModel.layout.nodes.map(\.id),
            rect: { viewModel.nodeRect($0) }
        ).transform else { return }
        canvasScale = fit.scale
        canvasOffset = fit.offset
        savePositions()
    }
}
