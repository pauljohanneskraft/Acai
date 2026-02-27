import SwiftUI
import UMLCore
import UniformTypeIdentifiers

// MARK: - Canvas Right-Click Tracker

#if os(macOS)
/// An invisible NSView overlay that captures right-click events and records the
/// click location in canvas coordinates before the SwiftUI context menu appears.
private struct CanvasRightClickTracker: NSViewRepresentable {
    @Binding var canvasPoint: CGPoint
    let scale: CGFloat
    let offset: CGPoint

    func makeNSView(context: Context) -> RightClickView {
        let view = RightClickView()
        view.onRightMouseDown = { [self] screenPoint in
            // screenPoint is in the view's local coordinate system.
            let canvasX = (screenPoint.x - offset.x) / scale
            let canvasY = (screenPoint.y - offset.y) / scale
            canvasPoint = CGPoint(x: canvasX, y: canvasY)
        }
        return view
    }

    func updateNSView(_ nsView: RightClickView, context: Context) {
        nsView.onRightMouseDown = { [self] screenPoint in
            let canvasX = (screenPoint.x - offset.x) / scale
            let canvasY = (screenPoint.y - offset.y) / scale
            canvasPoint = CGPoint(x: canvasX, y: canvasY)
        }
    }

    class RightClickView: NSView {
        var onRightMouseDown: ((CGPoint) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Return nil so this view never intercepts normal hits (clicks, drags).
            // Right-click events are delivered via the responder chain regardless.
            return nil
        }

        override func rightMouseDown(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            // NSView coordinate system is flipped vs SwiftUI; convert y.
            let flippedY = bounds.height - location.y
            onRightMouseDown?(CGPoint(x: location.x, y: flippedY))
            super.rightMouseDown(with: event)
        }
    }
}
#else
private struct CanvasRightClickTracker: View {
    @Binding var canvasPoint: CGPoint
    let scale: CGFloat
    let offset: CGPoint
    var body: some View { Color.clear.allowsHitTesting(false) }
}
#endif

// MARK: - Resize Edge

private struct ResizeState {
    let startSize: CGSize
    let startPosition: CGPoint
}

/// Editor view for custom (user-created) diagrams.
/// Provides a canvas with drag-to-select, a catalog sidebar for adding nodes/edges,
/// and inline editing of node members.
struct CustomDiagramEditorView: View {
    let diagramID: UUID
    @EnvironmentObject private var browserModel: ProjectBrowserViewModel
    @StateObject private var viewModel = CustomDiagramEditorViewModel()

    @State private var canvasScale: CGFloat = 1.0
    @State private var canvasOffset: CGPoint = .zero
    @State private var dragStartPositions: [UUID: CGPoint] = [:]
    @State private var activeDragCanvasLocation: CGPoint?
    @State private var canvasAutoPanController = EdgeAutoPanController()
    @State private var activeResizeState: ResizeState?
    @State private var showDeleteConfirmation = false
    /// Tracks the last right-click location in screen coordinates for context menu insertion.
    @State private var lastRightClickCanvasPoint: CGPoint = .zero

    enum SidebarTab { case catalog, inspector }
    @State private var showSidebar = true
    @State private var sidebarTab: SidebarTab = .catalog

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
                    sidebarTab = .catalog
                    showSidebar.toggle()
                } label: {
                    Label("Catalog", systemImage: "square.grid.2x2")
                }

                Button {
                    sidebarTab = .inspector
                    showSidebar.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(viewModel.selectedNodeIDs.isEmpty && viewModel.selectedEdgeID == nil)
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
        .onChange(of: viewModel.selectedNodeIDs) { newSelection in
            if !newSelection.isEmpty {
                sidebarTab = .inspector
                showSidebar = true
            }
        }
        .onChange(of: viewModel.selectedEdgeID) { newSelection in
            if newSelection != nil {
                sidebarTab = .inspector
                showSidebar = true
            }
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
            }
            .hidden()
        }
        .alert(
            deleteAlertTitle,
            isPresented: $showDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                if let edgeID = viewModel.selectedEdgeID {
                    viewModel.removeEdge(edgeID)
                }
                for id in viewModel.selectedNodeIDs {
                    viewModel.removeNode(id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
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
                edgeLayer
                regularNodeLayer
                resizeHandleLayer
            }
        })
        .onPreferenceChange(CustomNodeSizePreferenceKey.self) { sizes in
            for (id, size) in sizes {
                viewModel.measuredNodeSizes[id] = size
            }
        }
        .overlay {
            CanvasRightClickTracker(canvasPoint: $lastRightClickCanvasPoint, scale: canvasScale, offset: canvasOffset)
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
        ForEach(DiagramElementKind.CatalogGroup.allCases, id: \.rawValue) { group in
            Menu(group.rawValue) {
                ForEach(DiagramElementKind.catalogItems(in: group)) { kind in
                    Button {
                        insertNode(kind: kind, at: lastRightClickCanvasPoint)
                    } label: {
                        Label(kind.displayName, systemImage: kind.systemImage)
                    }
                }
            }
        }
    }

    // MARK: - Insertion Helpers

    private func insertNode(kind: DiagramElementKind, at canvasPoint: CGPoint) {
        let name = "New" + kind.displayName
            .replacingOccurrences(of: " / ", with: "")
            .replacingOccurrences(of: " ", with: "")
        viewModel.addNode(kind: kind, name: name, at: canvasPoint)
    }

    private func handleCatalogDrop(providers: [NSItemProvider], screenLocation: CGPoint) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let kindID = object as? String else { return }
            guard let kind = DiagramElementKind.allCatalogItems.first(where: { $0.id == kindID }) else { return }
            let canvasPoint = CGPoint(
                x: (screenLocation.x - canvasOffset.x) / canvasScale,
                y: (screenLocation.y - canvasOffset.y) / canvasScale
            )
            DispatchQueue.main.async {
                insertNode(kind: kind, at: canvasPoint)
            }
        }
        return true
    }

    // MARK: - Edge Layer

    private var edgeLayer: some View {
        ForEach(viewModel.edges) { edge in
            let sourceRect = viewModel.nodeRect(edge.sourceNodeID)
            let targetRect = viewModel.nodeRect(edge.targetNodeID)

            // Reuse RelationshipEdgeView with a temporary DiagramEdge.
            let diagramEdge = DiagramEdge(
                id: edge.id.uuidString,
                sourceID: edge.sourceNodeID.uuidString,
                targetID: edge.targetNodeID.uuidString,
                kind: edge.kind
            )

            RelationshipEdgeView(
                edge: diagramEdge,
                sourceRect: sourceRect,
                targetRect: targetRect
            )
            .onTapGesture {
                viewModel.selectedEdgeID = (viewModel.selectedEdgeID == edge.id) ? nil : edge.id
            }
        }
    }

    // MARK: - Container Node Layer (lowest z-level)

    private var containerNodeLayer: some View {
        ForEach(viewModel.nodes.filter(\.isResizable).sorted(by: { $0.drawOrder < $1.drawOrder })) { node in
            nodeView(for: node)
        }
    }

    // MARK: - Regular Node Layer (highest z-level)

    private var regularNodeLayer: some View {
        ForEach(viewModel.nodes.filter({ !$0.isResizable }).sorted(by: { $0.drawOrder < $1.drawOrder })) { node in
            nodeView(for: node)
        }
    }

    private func nodeView(for node: CustomDiagramNode) -> some View {
        let pos = CGPoint(x: node.positionX, y: node.positionY)
        let size = viewModel.nodeSize(node.id)
        let selected = viewModel.selectedNodeIDs.contains(node.id)

        return nodeContent(node: node, size: size, isSelected: selected)
            .position(pos)
            .onTapGesture(count: 2) {
                viewModel.selectNode(node.id, extending: false)
                sidebarTab = .inspector
                showSidebar = true
            }
            .onTapGesture(count: 1) {
                #if os(macOS)
                let extending = NSEvent.modifierFlags.contains(.command)
                #else
                let extending = false
                #endif
                viewModel.selectNode(node.id, extending: extending)
            }
            .highPriorityGesture(nodeDragGesture(for: node.id))
            .contextMenu {
                Button {
                    viewModel.selectNode(node.id, extending: false)
                    sidebarTab = .inspector
                    showSidebar = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button {
                    viewModel.startRelationshipDrawing(from: node.id)
                } label: {
                    Label("Draw Relationship", systemImage: "arrow.right")
                }

                Divider()

                Button {
                    viewModel.moveNodeHigher(node.id)
                } label: {
                    Label("Move Higher", systemImage: "chevron.up")
                }

                Button {
                    viewModel.moveNodeLower(node.id)
                } label: {
                    Label("Move Lower", systemImage: "chevron.down")
                }

                Divider()

                Button(role: .destructive) {
                    viewModel.removeNode(node.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    @ViewBuilder
    private func nodeContent(node: CustomDiagramNode, size: CGSize, isSelected: Bool) -> some View {
        if node.isResizable {
            CustomNodeView(node: node, isSelected: isSelected, size: size)
                .frame(width: size.width, height: size.height)
                // Disable hit testing on the outer frame edges so resize handles
                // in the layer above can receive hover / drag.
                .contentShape(Rectangle().inset(by: 6))
        } else {
            CustomNodeView(node: node, isSelected: isSelected, size: nil)
                .fixedSize()
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: CustomNodeSizePreferenceKey.self,
                            value: [node.id: geo.size]
                        )
                    }
                )
        }
    }

    // MARK: - Resize Handle Layer

    private var resizeHandleLayer: some View {
        ForEach(viewModel.nodes.filter { $0.isResizable }) { node in
            let pos = CGPoint(x: node.positionX, y: node.positionY)
            let size = viewModel.nodeSize(node.id)
            edgeResizeHandles(for: node.id, at: pos, size: size)
        }
    }

    private func edgeResizeHandles(for id: UUID, at position: CGPoint, size: CGSize) -> some View {
        let handleSize: CGFloat = 16
        return Rectangle()
            .fill(Color.clear)
            #if os(macOS)
            .cursorOnHover(.closedHand)
            #endif
            .frame(width: handleSize, height: handleSize)
            .contentShape(Rectangle())
            .position(x: position.x + size.width / 2, y: position.y + size.height / 2)
            .gesture(edgeResizeGesture(for: id))
    }

    private func edgeResizeGesture(for id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if activeResizeState == nil {
                    activeResizeState = ResizeState(
                        startSize: viewModel.nodeSize(id),
                        startPosition: viewModel.nodePosition(id) ?? .zero
                    )
                }
                guard let state = activeResizeState else { return }
                let minW: CGFloat = 80, minH: CGFloat = 50

                let newW = max(minW, state.startSize.width + value.translation.width)
                let newH = max(minH, state.startSize.height + value.translation.height)
                let dw = newW - state.startSize.width
                let dh = newH - state.startSize.height
                viewModel.resizeNode(id, width: newW, height: newH)
                viewModel.moveNode(id, to: CGPoint(
                    x: state.startPosition.x + dw / 2,
                    y: state.startPosition.y + dh / 2
                ))
            }
            .onEnded { _ in
                activeResizeState = nil
                viewModel.save()
            }
    }

    // MARK: - Node Dragging (Group)

    private func nodeDragGesture(for id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if dragStartPositions.isEmpty {
                    if !viewModel.selectedNodeIDs.contains(id) {
                        viewModel.selectedNodeIDs = [id]
                    }
                    for nodeID in viewModel.selectedNodeIDs {
                        dragStartPositions[nodeID] = viewModel.nodePosition(nodeID)
                    }
                }
                let tx = value.translation.width
                let ty = value.translation.height
                for nodeID in viewModel.selectedNodeIDs {
                    guard let start = dragStartPositions[nodeID] else { continue }
                    viewModel.moveNode(nodeID, to: CGPoint(
                        x: start.x + tx,
                        y: start.y + ty
                    ))
                }
                if let start = dragStartPositions[id] {
                    activeDragCanvasLocation = CGPoint(
                        x: start.x + tx,
                        y: start.y + ty
                    )
                }
            }
            .onEnded { _ in
                dragStartPositions = [:]
                activeDragCanvasLocation = nil
                viewModel.save()
            }
    }

    // MARK: - Sidebar (Catalog + Inspector)

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            Picker("Sidebar", selection: $sidebarTab) {
                Text("Catalog").tag(SidebarTab.catalog)
                Text("Inspector").tag(SidebarTab.inspector)
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch sidebarTab {
            case .catalog:
                catalogSidebarContent
            case .inspector:
                inspectorSidebarContent
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var catalogSidebarContent: some View {
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

    private func catalogSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
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
            insertNode(kind: kind, at: CGPoint(x: centerX, y: centerY))
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

    // MARK: - Inspector Sidebar

    @State private var inspectorNodeName: String = ""
    @State private var inspectorNodeKind: DiagramElementKind = .type(.class)
    @State private var inspectorNoteText: String = ""
    @State private var newPropertyText: String = ""
    @State private var newMethodText: String = ""

    @State private var inspectorEdgeSourceID: UUID?
    @State private var inspectorEdgeTargetID: UUID?
    @State private var inspectorEdgeKind: Relationship.Kind = .association

    @ViewBuilder
    private var inspectorSidebarContent: some View {
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

    // MARK: Node Inspector

    private func nodeInspector(node: CustomDiagramNode) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Name
                Section {
                    TextField("Name", text: Binding(
                        get: { node.name },
                        set: { viewModel.updateNode(node.id, name: $0, kind: node.content.elementKind) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.headline)
                } header: {
                    Text("Name").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                }

                // Kind picker
                Section {
                    Picker("Kind", selection: Binding(
                        get: { node.content.elementKind },
                        set: { viewModel.updateNode(node.id, name: node.name, kind: $0) }
                    )) {
                        ForEach(DiagramElementKind.CatalogGroup.allCases, id: \.rawValue) { group in
                            Section(group.rawValue) {
                                ForEach(DiagramElementKind.catalogItems(in: group)) { elementKind in
                                    Text(elementKind.displayName).tag(elementKind)
                                }
                            }
                        }
                    }
                    .labelsHidden()
                } header: {
                    Text("Kind").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                }

                // Position
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

                // Type-specific: Properties & Methods
                if case .type(let content) = node.content {
                    propertiesSection(nodeID: node.id, content: content)
                    methodsSection(nodeID: node.id, content: content)
                }

                // Note-specific: Text
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

                // Relationships for this node
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

                // Delete button
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

    private func propertiesSection(nodeID: UUID, content: TypeNodeContent) -> some View {
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

    private func methodsSection(nodeID: UUID, content: TypeNodeContent) -> some View {
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

    // MARK: Edge Inspector

    private func edgeInspector(edge: CustomDiagramEdge) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Section {
                    Picker("Source", selection: Binding(
                        get: { edge.sourceNodeID },
                        set: { newSource in
                            viewModel.updateEdge(
                                edge.id,
                                sourceID: newSource,
                                targetID: edge.targetNodeID,
                                kind: edge.kind
                            )
                        }
                    )) {
                        ForEach(viewModel.nodes) { node in
                            Text(node.name).tag(node.id)
                        }
                    }

                    Picker("Target", selection: Binding(
                        get: { edge.targetNodeID },
                        set: { newTarget in
                            viewModel.updateEdge(
                                edge.id,
                                sourceID: edge.sourceNodeID,
                                targetID: newTarget,
                                kind: edge.kind
                            )
                        }
                    )) {
                        ForEach(viewModel.nodes) { node in
                            Text(node.name).tag(node.id)
                        }
                    }

                    Picker("Kind", selection: Binding(
                        get: { edge.kind },
                        set: { newKind in
                            viewModel.updateEdge(
                                edge.id,
                                sourceID: edge.sourceNodeID,
                                targetID: edge.targetNodeID,
                                kind: newKind
                            )
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

                let sourceName = viewModel.nodes.first(where: { $0.id == edge.sourceNodeID })?.name ?? "?"
                let targetName = viewModel.nodes.first(where: { $0.id == edge.targetNodeID })?.name ?? "?"
                Text("\(sourceName) → \(targetName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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

    // MARK: Multi-Node Inspector

    private var multiNodeInspector: some View {
        VStack(spacing: 12) {
            Text("\(viewModel.selectedNodeIDs.count) nodes selected")
                .font(.headline)

            List {
                ForEach(Array(viewModel.selectedNodeIDs), id: \.self) { nodeID in
                    if let node = viewModel.nodes.first(where: { $0.id == nodeID }) {
                        HStack {
                            Image(systemName: node.content.elementKind.systemImage)
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

// MARK: - Custom Node View (dispatcher)

/// Dispatches to the appropriate shared UML node view based on the node's content.
struct CustomNodeView: View {
    let node: CustomDiagramNode
    let isSelected: Bool
    /// Explicit size for resizable container nodes. `nil` for auto-sized nodes.
    var size: CGSize?

    var body: some View {
        switch node.content {
        case .type(let content):
            UMLTypeBoxView(node: node, content: content, isSelected: isSelected)
        case .note(let text):
            UMLNoteNodeView(name: node.name, text: text, isSelected: isSelected)
        case .actor:
            UMLActorNodeView(name: node.name, isSelected: isSelected)
        case .useCase:
            UMLUseCaseNodeView(name: node.name, isSelected: isSelected)
        case .package:
            UMLContainerNodeView(
                name: node.name, stereotype: "package",
                style: .package, isSelected: isSelected, size: size
            )
        case .boundary:
            UMLContainerNodeView(
                name: node.name, stereotype: "boundary",
                style: .boundary, isSelected: isSelected, size: size
            )
        case .subsystem:
            UMLContainerNodeView(
                name: node.name, stereotype: "subsystem",
                style: .subsystem, isSelected: isSelected, size: size
            )
        case .database:
            UMLDatabaseNodeView(name: node.name, isSelected: isSelected)
        default:
            // component, deploymentNode, artifact, entity
            UMLStereotypedBoxNodeView(
                name: node.name,
                stereotype: node.content.stereotype,
                systemImage: node.content.elementKind.systemImage,
                isSelected: isSelected
            )
        }
    }
}

// MARK: - DiagramEdge convenience init for custom diagrams.

extension DiagramEdge {
    init(id: String, sourceID: String, targetID: String, kind: Relationship.Kind) {
        self.id = id
        self.sourceID = sourceID
        self.targetID = targetID
        self.kind = kind
    }
}
