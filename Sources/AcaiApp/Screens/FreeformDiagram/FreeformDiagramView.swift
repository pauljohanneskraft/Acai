import SwiftUI
import AcaiCore
import UniformTypeIdentifiers

@MainActor
struct FreeformDiagramView: View {
    let diagramID: UUID
    @EnvironmentObject private var browserModel: ProjectBrowserViewModel
    @StateObject var viewModel = FreeformDiagramViewModel()

    // Not `private`: `FreeformDiagramView+Placement.swift` (a same-type extension in another file)
    // reads these to compute the placement ghost position and the commit-tap's canvas point.
    @State var canvasScale: CGFloat = 1.0
    @State var canvasOffset: CGPoint = .zero
    @State var dragStartPositions: [String: CGPoint] = [:]
    @State var activeDragCanvasLocation: CGPoint?
    @State private var canvasAutoPanController = EdgeAutoPanController()
    @State var activeResizeState: DiagramResizeState?
    // Not `private`: `FreeformDiagramView+Canvas.swift`'s `canvasContextMenu` sets this too.
    @State var showDeleteConfirmation = false
    @State var cursorLocation: CGPoint = .zero
    @State private var canvasViewportSize = CGSize(width: 900, height: 600)
    @State private var showCheckpoints = false
    /// True while a text field in the inspector is focused, so the diagram-level ⌘Z/⇧⌘Z
    /// shortcuts yield to the field's native text undo.
    @State private var isEditingText = false

    enum SidebarTab { case catalog, inspector }
    @State var showSidebar = false
    @State var sidebarTab: SidebarTab = .catalog
    // Not `private`: `FreeformDiagramView+Placement.swift` reads this via `isCompactWidth`.
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif

    /// `.place` shows `FreeformBottomToolbar`'s catalog strip above the bar so a node kind can be
    /// picked without ever opening the sidebar.
    enum BottomBarMode: Hashable { case select, place }
    @State private var bottomBarMode: BottomBarMode = .select

    var body: some View {
        canvasArea
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if !os(macOS)
            // Let the canvas draw full-bleed under the floating toolbar and past the home
            // indicator, like a native drawing/canvas app, instead of stopping at the safe area.
            .ignoresSafeArea()
            #endif
            .onGeometryChange(for: CGSize.self) { $0.size } action: { canvasViewportSize = $0 }
            .inspector(isPresented: $showSidebar) {
                sidebarContent
                    .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
            }
            .onChange(of: viewModel.pendingPlacement) { _, newValue in
                beginningPlacementClosesCompactSidebar(newValue)
            }
            #if os(iOS)
            .onChange(of: bottomBarMode) { _, newValue in
                if newValue == .select {
                    viewModel.cancelPlacement()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if horizontalSizeClass == .compact, bottomBarMode == .place {
                    FreeformBottomToolbar(viewModel: viewModel)
                }
            }
            #endif
            .toolbar {
                ToolbarItemGroup {
                    UndoRedoToolbarButtons(model: viewModel, onChange: {})
                    #if !os(macOS)
                    MultiSelectToggleButton(model: viewModel)
                    #endif

                    Button {
                        centerDiagram()
                    } label: {
                        Label(.app("View.FreeformDiagramView.FitView"), systemImage: "rectangle.dashed")
                    }
                    .help(.app("View.FreeformDiagramView.FitDiagramVisibleCanvas"))
                    .keyboardShortcut("0", modifiers: .command)
                    .accessibilityIdentifier("diagram.fitToViewButton")

                    Button {
                        showCheckpoints = true
                    } label: {
                        Label(.app("View.FreeformDiagramView.Checkpoints"), systemImage: "clock.arrow.circlepath")
                    }
                    .help(.app("View.FreeformDiagramView.SaveRestoreNamedSnapshot"))
                    .accessibilityIdentifier("diagram.checkpointsButton")

                    Button {
                        sidebarTab = .catalog
                        showSidebar.toggle()
                    } label: {
                        Label(.app("View.FreeformDiagramView.Sidebar"), systemImage: "sidebar.trailing")
                    }
                    .help(.app("View.FreeformDiagramView.ToggleNodeCatalogInspector"))
                    .accessibilityIdentifier("diagram.sidebarToggleButton")
                }
                #if os(iOS)
                if horizontalSizeClass == .compact {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Picker(.app("View.FreeformDiagramView.BottomBarMode"), selection: $bottomBarMode) {
                            Label(.app("View.FreeformDiagramView.Select"), systemImage: "cursorarrow")
                                .tag(BottomBarMode.select)
                            Label(.app("View.FreeformDiagramView.Place"), systemImage: "plus.square.on.square")
                                .tag(BottomBarMode.place)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityIdentifier("diagram.bottomBar.modePicker")

                        Spacer()

                        Button {
                            viewModel.applyLastUsedConnectionTool()
                        } label: {
                            Label(
                                .app("View.FreeformDiagramView.QuickAdd"),
                                systemImage: viewModel.lastUsedConnectionToolSystemImage
                            )
                        }
                        .disabled(!viewModel.canApplyLastUsedConnectionTool)
                        .accessibilityIdentifier("diagram.bottomBar.quickAddButton")
                    }
                }
                #endif
            }
            #if os(macOS)
            .navigationTitle(browserModel.freeformDiagram(for: diagramID)?.name ?? "Freeform Diagram")
            #else
            // A large title would eat vertical space from the canvas for little benefit — the
            // back button already carries the project context, so the diagram screen goes titleless.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                viewModel.configure(diagramID: diagramID, browserModel: browserModel)
                if let diagram = browserModel.freeformDiagram(for: diagramID) {
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
                // Hidden buttons to capture keyboard shortcuts (external keyboard on iPad/Mac). Touch
                // users reach the same actions via `canvasContextMenu`'s selection section below.
                Group {
                    Button("") {
                        if !viewModel.selectedNodeIDs.isEmpty || viewModel.selectedEdgeID != nil {
                            showDeleteConfirmation = true
                        }
                    }
                    .keyboardShortcut(.delete, modifiers: [])

                    Button("") { viewModel.clipboard.copySelection() }
                        .keyboardShortcut("c", modifiers: .command)

                    Button("") { viewModel.clipboard.cutSelection() }
                        .keyboardShortcut("x", modifiers: .command)

                    Button("") { viewModel.clipboard.paste() }
                        .keyboardShortcut("v", modifiers: .command)

                    Button("") { viewModel.selectAll() }
                        .keyboardShortcut("a", modifiers: .command)
                }
                .hidden()
            }
            .undoRedoKeyboardShortcuts(model: viewModel, enabled: !isEditingText, onChange: {})
            .alert(
                deleteAlertTitle,
                isPresented: $showDeleteConfirmation
            ) {
                Button(.app("View.FreeformDiagramView.Delete"), role: .destructive) {
                    viewModel.deleteSelection()
                }
                Button(.app("View.FreeformDiagramView.Cancel"), role: .cancel) {}
            } message: {
                Text(.app("View.FreeformDiagramView.CanUndoActionZ"))
            }
            .sheet(isPresented: $showCheckpoints) {
                FreeformDiagramCheckpointsView(viewModel: viewModel)
            }
    }

    private var deleteAlertTitle: LocalizedStringResource {
        if viewModel.selectedEdgeID != nil && viewModel.selectedNodeIDs.isEmpty {
            return .app("View.FreeformDiagramView.DeleteRelationship")
        }
        return .app("View.FreeformDiagramView.DeleteNodes \(viewModel.selectedNodeIDs.count)")
    }

    // MARK: - Canvas

    private var canvasArea: some View {
        PannableCanvas(
            model: viewModel,
            scale: $canvasScale,
            offset: $canvasOffset,
            activeDragCanvasLocation: activeDragCanvasLocation,
            autoPanController: canvasAutoPanController,
            onBackgroundTap: handleBackgroundTap
        ) {
            ZStack {
                containerNodeLayer
                sequenceLayer
                regularNodeLayer
                edgeLayer
                resizeHandleLayer
            }
            // While a catalog placement is pending, nodes stop intercepting taps so *any* tap on the
            // canvas — background or over an existing node — reaches `handleBackgroundTap` and
            // commits the placement there, instead of selecting/dragging whatever's underneath.
            .allowsHitTesting(viewModel.pendingPlacement == nil)
        }
        .onPreferenceChange(NodeSizePreferenceKey.self) { sizes in
            for (id, size) in sizes {
                viewModel.measuredNodeSizes[id] = size
            }
        }
        .onContinuousHover { phase in
            if case let .active(location) = phase {
                cursorLocation = location
            }
        }
        #if !os(macOS)
        // No hover on touch, so `cursorLocation` would otherwise stay at its initial `.zero` —
        // track the long-press's own touch-down location instead, so the context menu's "add node"
        // inserts under the finger rather than at a fixed, stale point.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).onChanged { value in
                cursorLocation = value.location
            }
        )
        #endif
        .contextMenu {
            canvasContextMenu
        }
        .onDrop(of: [.text], isTargeted: nil) { providers, location in
            handleCatalogDrop(providers: providers, screenLocation: location)
        }
        .overlay {
            if viewModel.nodes.isEmpty && viewModel.pendingPlacement == nil {
                emptyCanvasHint
            }
        }
        .overlay {
            placementGhostOverlay
        }
        .overlay(alignment: .topTrailing) {
            placementCancelButton
        }
        .background {
            // Hidden button so Escape (macOS, external keyboard on iPad) backs out of placement
            // mode — the explicit "or Escape key" cancel affordance alongside `placementCancelButton`.
            Button("") { viewModel.cancelPlacement() }
                .keyboardShortcut(.cancelAction)
                .hidden()
        }
    }

    private var emptyCanvasHint: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.draw")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(.app("View.FreeformDiagramView.CanvasEmpty"))
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(localized: emptyCanvasHintText)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .allowsHitTesting(false)
    }

    private var emptyCanvasHintText: LocalizedStringResource {
        #if os(macOS)
        .app("View.FreeformDiagramView.RightClickToAddNode")
        #else
        .app("View.FreeformDiagramView.TouchAndHoldToAddNode")
        #endif
    }

    // MARK: - Canvas Fit

    private func centerDiagram() {
        guard let fit = FitToView(
            nodeIDs: viewModel.allNodeIDs,
            rect: { viewModel.nodeRect($0) },
            viewport: canvasViewportSize
        ).transform else { return }
        canvasScale = fit.scale
        canvasOffset = fit.offset
        viewModel.saveCanvasState(scale: canvasScale, offset: canvasOffset)
    }

    // MARK: - Insertion Helpers

    // Not `private`: `FreeformDiagramView+Canvas.swift`'s `canvasContextMenu` calls this too.
    func insertNode(kind: FreeformDiagramNodeKind, at canvasPoint: CGPoint) {
        viewModel.addNode(kind: kind, name: kind.defaultNodeName, at: canvasPoint)
    }

    private func handleCatalogDrop(providers: [NSItemProvider], screenLocation: CGPoint) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let kindID = object as? String else { return }
            guard let kind = FreeformDiagramNodeKind.allCases.first(where: { $0.id == kindID }) else { return }
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
                Text(.app("View.FreeformDiagramView.Catalog")).tag(SidebarTab.catalog)
                Text(.app("View.FreeformDiagramView.Inspector")).tag(SidebarTab.inspector)
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch sidebarTab {
            case .catalog:
                FreeformDiagramCatalog(viewModel: viewModel)
            case .inspector:
                FreeformDiagramInspector(viewModel: viewModel, isEditingText: $isEditingText)
            }
        }
        .background {
            #if os(macOS)
            Color(nsColor: .controlBackgroundColor)
            #else
            Color(uiColor: .secondarySystemBackground)
            #endif
        }
    }
}
