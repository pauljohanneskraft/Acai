import SwiftUI
import UMLCore
import UMLDiagram
import UMLRender

/// Movement-only view for a generated static call graph. Derives the graph from the artifact and
/// lets the user drag method nodes on the shared canvas layer (`PannableCanvas`, drag gesture,
/// undo/redo) like the package view. Methods render as rounded boxes (in-scope solid, out-of-scope
/// callees dashed); calls are arrows whose thickness encodes their multiplicity. A banner reports
/// how much of the observed call traffic could be statically resolved.
struct CallGraphView: View {
    let diagram: GeneratedDiagram
    let artifact: CodeArtifact
    let codebase: Codebase

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @StateObject private var viewModel: CallGraphViewModel

    @State private var canvasScale: CGFloat
    @State private var canvasOffset: CGPoint
    @State private var dragStartPositions: [String: CGPoint] = [:]
    @State private var activeDragCanvasLocation: CGPoint?
    @State private var canvasAutoPanController = EdgeAutoPanController()

    init(diagram: GeneratedDiagram, artifact: CodeArtifact, codebase: Codebase) {
        self.diagram = diagram
        self.artifact = artifact
        self.codebase = codebase
        let scope: CallGraphScope
        if case .callGraph(let configured) = diagram.content { scope = configured } else { scope = .wholeCodebase }
        self._viewModel = StateObject(wrappedValue: CallGraphViewModel(
            artifact: artifact,
            scope: scope,
            restoredPositions: diagram.nodePositions.mapValues(\.cgPoint)
        ))
        self._canvasScale = State(initialValue: CGFloat(diagram.canvasScale))
        self._canvasOffset = State(initialValue: CGPoint(x: diagram.canvasOffsetX, y: diagram.canvasOffsetY))
    }

    var body: some View {
        canvasContent
            .overlay(alignment: .top) { coverageBanner }
            .toolbar { toolbarContent }
            .undoRedoKeyboardShortcuts(model: viewModel, onChange: savePositions)
            .navigationTitle(diagram.name)
            .task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1))
                centerDiagram()
            }
            .onDisappear { savePositions() }
    }

    // MARK: - Coverage banner

    private var coverageBanner: some View {
        let coverage = viewModel.graph.coverage
        let percent = Int((coverage.fraction * 100).rounded())
        return HStack(spacing: 6) {
            Image(systemName: percent == 100 ? "checkmark.seal" : "exclamationmark.triangle")
            Text("Resolved \(coverage.resolved)/\(coverage.total) call sites (\(percent)%)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
        .padding(.top, 8)
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
                callEdges(layout)
                ForEach(layout.nodes) { node in
                    methodNode(node)
                }
            }
        }
    }

    private func callEdges(_ layout: CallGraphLayoutModel) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.edges) { edge in
                if let sourceRect = layout.frame(for: edge.from),
                   let targetRect = layout.frame(for: edge.to) {
                    RelationshipEdgeView(
                        kind: .dependency,
                        sourceRect: sourceRect,
                        targetRect: targetRect,
                        lineWidthScale: Self.lineWidthScale(forWeight: edge.weight)
                    )
                }
            }
        }
    }

    private func methodNode(_ node: CallGraphLayoutModel.NodeFrame) -> some View {
        CallGraphNodeView(
            node: node.node,
            isSelected: viewModel.selectedNodeIDs.contains(node.id)
        )
        .frame(width: node.rect.width, height: node.rect.height)
        .position(x: node.rect.midX, y: node.rect.midY)
        .onTapGesture {
            #if os(macOS)
            let extending = NSEvent.modifierFlags.contains(.command)
            #else
            let extending = false
            #endif
            viewModel.selectNode(node.id, extending: extending)
        }
        .highPriorityGesture(canvasNodeDragGesture(
            id: node.id,
            model: viewModel,
            dragStartPositions: $dragStartPositions,
            activeDragCanvasLocation: $activeDragCanvasLocation,
            onCommit: savePositions
        ))
    }

    /// Maps a call's multiplicity to a line-width multiplier, clamped so the heaviest edges stay legible.
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
        }
    }

    // MARK: - Persistence & layout

    private func savePositions() {
        model.updateGeneratedDiagramPositions(
            diagramID: diagram.id,
            positions: viewModel.positionOverrides,
            scale: canvasScale,
            offset: canvasOffset
        )
    }

    private func centerDiagram() {
        guard let fit = fitToView(
            nodeIDs: viewModel.layout.nodes.map(\.id),
            rect: { viewModel.nodeRect($0) }
        ) else { return }
        canvasScale = fit.scale
        canvasOffset = fit.offset
        savePositions()
    }
}

/// A single method box in the call graph: `Type.method`, solid for in-scope methods and dashed +
/// lighter for out-of-scope callee leaves so the focus stands out.
private struct CallGraphNodeView: View {
    let node: CallGraph.Node
    let isSelected: Bool

    private var fill: Color {
        node.inScope ? Color(red: 0.89, green: 0.95, blue: 0.99) : Color(white: 0.96)
    }

    var body: some View {
        Text(node.label)
            .font(.system(.caption, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(fill))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color(white: 0.6),
                        style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: node.inScope ? [] : [4, 3])
                    )
            )
    }
}
