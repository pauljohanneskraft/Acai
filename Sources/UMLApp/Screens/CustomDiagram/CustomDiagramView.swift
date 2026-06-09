import SwiftUI
import UMLCore
import UniformTypeIdentifiers

/// Editor view for custom (user-created) diagrams.
/// Provides a canvas with drag-to-select, a catalog sidebar for adding nodes/edges,
/// and inline editing of node members.
@MainActor
struct CustomDiagramView: View {
    let diagramID: UUID
    @EnvironmentObject private var browserModel: ProjectBrowserViewModel
    @StateObject var viewModel = CustomDiagramViewModel()

    @State private var canvasScale: CGFloat = 1.0
    @State private var canvasOffset: CGPoint = .zero
    @State var dragStartPositions: [UUID: CGPoint] = [:]
    @State var activeDragCanvasLocation: CGPoint?
    @State private var canvasAutoPanController = EdgeAutoPanController()
    @State var activeResizeState: DiagramResizeState?
    @State private var showDeleteConfirmation = false
    @State private var cursorLocation: CGPoint = .zero

    enum SidebarTab { case catalog, inspector }
    @State var showSidebar = false
    @State var sidebarTab: SidebarTab = .catalog

    var body: some View {
        HSplitView {
            // Main canvas
            canvasArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Combined Catalog / Inspector sidebar
            if showSidebar {
                sidebarContent
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    viewModel.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!viewModel.canUndo)
                .help("Undo (⌘Z)")

                Button {
                    viewModel.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!viewModel.canRedo)
                .help("Redo (⇧⌘Z)")

                Button {
                    sidebarTab = .catalog
                    showSidebar.toggle()
                } label: {
                    Label("Sidebar", systemImage: "sidebar.trailing")
                }
            }
        }
        .navigationTitle(browserModel.customDiagram(for: diagramID)?.name ?? "Custom Diagram")
        .onAppear {
            viewModel.configure(diagramID: diagramID, browserModel: browserModel)
            if let diagram = browserModel.customDiagram(for: diagramID) {
                if diagram.canvasScale > 0.01 {
                    canvasScale = CGFloat(diagram.canvasScale)
                    canvasOffset = CGPoint(x: diagram.canvasOffsetX, y: diagram.canvasOffsetY)
                }
            }
        }
        .onDisappear {
            viewModel.saveCanvasState(scale: canvasScale, offset: canvasOffset)
        }
        .background {
            // Hidden buttons to capture keyboard shortcuts
            Group {
                Button("") {
                    if !viewModel.selectedNodeIDs.isEmpty || viewModel.selectedEdgeID != nil {
                        showDeleteConfirmation = true
                    }
                }
                .keyboardShortcut(.delete, modifiers: [])

                Button("") { viewModel.copySelection() }
                    .keyboardShortcut("c", modifiers: .command)

                Button("") { viewModel.cutSelection() }
                    .keyboardShortcut("x", modifiers: .command)

                Button("") { viewModel.paste() }
                    .keyboardShortcut("v", modifiers: .command)

                Button("") { viewModel.selectAll() }
                    .keyboardShortcut("a", modifiers: .command)

                Button("") { viewModel.undo() }
                    .keyboardShortcut("z", modifiers: .command)

                Button("") { viewModel.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            .hidden()
        }
        .alert(
            deleteAlertTitle,
            isPresented: $showDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                viewModel.deleteSelection()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can undo this action with ⌘Z.")
        }
    }

    private var deleteAlertTitle: String {
        if viewModel.selectedEdgeID != nil && viewModel.selectedNodeIDs.isEmpty {
            return "Delete Relationship?"
        }
        let count = viewModel.selectedNodeIDs.count
        return count == 1 ? "Delete Node?" : "Delete \(count) Nodes?"
    }

    // MARK: - Canvas

    private var canvasArea: some View {
        InfiniteCanvas(scale: $canvasScale, offset: $canvasOffset, onSelectionRect: { rect in
            viewModel.selectNodes(in: rect)
        }, onBackgroundTap: {
            viewModel.clearSelection()
        }, autoPanDragLocation: activeDragCanvasLocation, onAutoPanDelta: { canvasDelta in
            for nodeID in viewModel.selectedNodeIDs {
                if let pos = viewModel.nodePosition(nodeID) {
                    viewModel.moveNode(nodeID, to: CGPoint(
                        x: pos.x + canvasDelta.width,
                        y: pos.y + canvasDelta.height
                    ))
                }
            }
        }, autoPanController: canvasAutoPanController, content: {
            ZStack {
                containerNodeLayer
                regularNodeLayer
                edgeLayer
                resizeHandleLayer
            }
        })
        .onPreferenceChange(NodeSizePreferenceKey.self) { sizes in
            for (id, size) in sizes {
                viewModel.measuredNodeSizes[UUID(uuidString: id) ?? UUID()] = size
            }
        }
        .onContinuousHover { phase in
            if case let .active(location) = phase {
                cursorLocation = location
            }
        }
        .contextMenu {
            canvasContextMenu
        }
        .onDrop(of: [.text], isTargeted: nil) { providers, location in
            handleCatalogDrop(providers: providers, screenLocation: location)
        }
    }

    // MARK: - Canvas Context Menu

    @ViewBuilder
    private var canvasContextMenu: some View {
        ForEach(CustomDiagramNodeKind.CatalogGroup.allCases, id: \.rawValue) { group in
            Menu(group.rawValue) {
                ForEach(CustomDiagramNodeKind.cases(in: group)) { kind in
                    Button {
                        let canvasPoint = CGPoint(
                            x: (cursorLocation.x - canvasOffset.x) / canvasScale,
                            y: (cursorLocation.y - canvasOffset.y) / canvasScale
                        )
                        insertNode(kind: kind, at: canvasPoint)
                    } label: {
                        Label(kind.displayName, systemImage: kind.systemImage)
                    }
                }
            }
        }
    }

    // MARK: - Insertion Helpers

    private func insertNode(kind: CustomDiagramNodeKind, at canvasPoint: CGPoint) {
        let name = "New" + kind.displayName
            .replacingOccurrences(of: " / ", with: "")
            .replacingOccurrences(of: " ", with: "")
        viewModel.addNode(kind: kind, name: name, at: canvasPoint)
    }

    private func handleCatalogDrop(providers: [NSItemProvider], screenLocation: CGPoint) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let kindID = object as? String else { return }
            guard let kind = CustomDiagramNodeKind.allCases.first(where: { $0.id == kindID }) else { return }
            Task { @MainActor in
                let canvasPoint = CGPoint(
                    x: (screenLocation.x - canvasOffset.x) / canvasScale,
                    y: (screenLocation.y - canvasOffset.y) / canvasScale
                )
                insertNode(kind: kind, at: canvasPoint)
            }
        }
        return true
    }

    // MARK: - Sidebar (Catalog + Inspector)

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            Picker("", selection: $sidebarTab) {
                Text("Catalog").tag(SidebarTab.catalog)
                Text("Inspector").tag(SidebarTab.inspector)
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch sidebarTab {
            case .catalog:
                CustomDiagramCatalog(
                    viewModel: viewModel,
                    canvasScale: canvasScale,
                    canvasOffset: canvasOffset,
                    onInsertNode: insertNode
                )
            case .inspector:
                CustomDiagramInspector(viewModel: viewModel)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
