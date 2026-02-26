import SwiftUI
import UMLCore
import UniformTypeIdentifiers

// MARK: - Identifiable UUID Wrapper

/// Wraps a UUID to conform to Identifiable, for use with `.sheet(item:)`.
private struct IdentifiableUUID: Identifiable {
    let value: UUID
    var id: UUID { value }
    init(_ value: UUID) { self.value = value }
}

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

private enum ResizeEdge {
    case left, right, top, bottom
}

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
    @State private var activeDragCanvasLocation: CGPoint? = nil
    @State private var canvasAutoPanController = EdgeAutoPanController()
    @State private var activeResizeState: ResizeState? = nil
    @State private var showingCatalog = false
    @State private var editingNodeID: IdentifiableUUID? = nil
    @State private var showingEdgeCreator = false
    @State private var edgeSourceID: UUID? = nil
    @State private var showDeleteConfirmation = false
    /// Tracks the last right-click location in screen coordinates for context menu insertion.
    @State private var lastRightClickCanvasPoint: CGPoint = .zero

    var body: some View {
        HStack(spacing: 0) {
            // Main canvas
            canvasArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Catalog / Inspector sidebar
            if showingCatalog {
                Divider()
                catalogSidebar
                    .frame(width: 240)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showingCatalog.toggle()
                } label: {
                    Label("Catalog", systemImage: "square.grid.2x2")
                }

                Button {
                    if let first = viewModel.selectedNodeIDs.first {
                        editingNodeID = IdentifiableUUID(first)
                    }
                } label: {
                    Label("Edit Node", systemImage: "pencil")
                }
                .disabled(viewModel.selectedNodeIDs.count != 1)

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(viewModel.selectedNodeIDs.isEmpty)
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
        .sheet(item: $editingNodeID) { item in
            CustomNodeEditorSheet(viewModel: viewModel, nodeID: item.value)
        }
        .sheet(isPresented: $showingEdgeCreator) {
            CustomEdgeCreatorSheet(viewModel: viewModel, sourceNodeID: edgeSourceID)
        }
        .background {
            // Hidden button to capture backspace / delete key
            Button("") {
                if !viewModel.selectedNodeIDs.isEmpty {
                    showDeleteConfirmation = true
                }
            }
            .keyboardShortcut(.delete, modifiers: [])
            .hidden()
        }
        .alert(
            "Delete \(viewModel.selectedNodeIDs.count == 1 ? "Node" : "\(viewModel.selectedNodeIDs.count) Nodes")?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                for id in viewModel.selectedNodeIDs {
                    viewModel.removeNode(id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
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
        }, autoPanController: canvasAutoPanController) {
            ZStack {
                containerNodeLayer
                edgeLayer
                regularNodeLayer
                resizeHandleLayer
            }
        }
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
        let name = "New\(kind.displayName.replacingOccurrences(of: " / ", with: "").replacingOccurrences(of: " ", with: ""))"
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
                editingNodeID = IdentifiableUUID(node.id)
            }
            .onTapGesture(count: 1) {
                #if os(macOS)
                let extending = NSEvent.modifierFlags.contains(.shift)
                #else
                let extending = false
                #endif
                viewModel.selectNode(node.id, extending: extending)
            }
            .highPriorityGesture(nodeDragGesture(for: node.id))
            .contextMenu {
                Button {
                    editingNodeID = IdentifiableUUID(node.id)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button {
                    edgeSourceID = node.id
                    showingEdgeCreator = true
                } label: {
                    Label("Add Edge From Here", systemImage: "arrow.right")
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
        ForEach(viewModel.nodes.filter { $0.isResizable && viewModel.selectedNodeIDs.contains($0.id) }) { node in
            let pos = CGPoint(x: node.positionX, y: node.positionY)
            let size = viewModel.nodeSize(node.id)
            edgeResizeHandles(for: node.id, at: pos, size: size)
        }
    }

    private func edgeResizeHandles(for id: UUID, at position: CGPoint, size: CGSize) -> some View {
        let thickness: CGFloat = 8
        return ZStack {
            // Right edge
            Rectangle()
                .fill(Color.clear)
                .frame(width: thickness, height: size.height)
                .contentShape(Rectangle())
                .position(x: position.x + size.width / 2, y: position.y)
                .gesture(edgeResizeGesture(for: id, edge: .right))
                #if os(macOS)
                .onHover { h in if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                #endif

            // Left edge
            Rectangle()
                .fill(Color.clear)
                .frame(width: thickness, height: size.height)
                .contentShape(Rectangle())
                .position(x: position.x - size.width / 2, y: position.y)
                .gesture(edgeResizeGesture(for: id, edge: .left))
                #if os(macOS)
                .onHover { h in if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                #endif

            // Bottom edge
            Rectangle()
                .fill(Color.clear)
                .frame(width: size.width, height: thickness)
                .contentShape(Rectangle())
                .position(x: position.x, y: position.y + size.height / 2)
                .gesture(edgeResizeGesture(for: id, edge: .bottom))
                #if os(macOS)
                .onHover { h in if h { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                #endif

            // Top edge
            Rectangle()
                .fill(Color.clear)
                .frame(width: size.width, height: thickness)
                .contentShape(Rectangle())
                .position(x: position.x, y: position.y - size.height / 2)
                .gesture(edgeResizeGesture(for: id, edge: .top))
                #if os(macOS)
                .onHover { h in if h { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                #endif
        }
    }

    private func edgeResizeGesture(for id: UUID, edge: ResizeEdge) -> some Gesture {
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

                switch edge {
                case .right:
                    let newW = max(minW, state.startSize.width + value.translation.width)
                    let dw = newW - state.startSize.width
                    viewModel.resizeNode(id, width: newW, height: state.startSize.height)
                    viewModel.moveNode(id, to: CGPoint(
                        x: state.startPosition.x + dw / 2,
                        y: state.startPosition.y
                    ))
                case .left:
                    let newW = max(minW, state.startSize.width - value.translation.width)
                    let dw = newW - state.startSize.width
                    viewModel.resizeNode(id, width: newW, height: state.startSize.height)
                    viewModel.moveNode(id, to: CGPoint(
                        x: state.startPosition.x - dw / 2,
                        y: state.startPosition.y
                    ))
                case .bottom:
                    let newH = max(minH, state.startSize.height + value.translation.height)
                    let dh = newH - state.startSize.height
                    viewModel.resizeNode(id, width: state.startSize.width, height: newH)
                    viewModel.moveNode(id, to: CGPoint(
                        x: state.startPosition.x,
                        y: state.startPosition.y + dh / 2
                    ))
                case .top:
                    let newH = max(minH, state.startSize.height - value.translation.height)
                    let dh = newH - state.startSize.height
                    viewModel.resizeNode(id, width: state.startSize.width, height: newH)
                    viewModel.moveNode(id, to: CGPoint(
                        x: state.startPosition.x,
                        y: state.startPosition.y - dh / 2
                    ))
                }
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

    // MARK: - Catalog Sidebar

    private var catalogSidebar: some View {
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
            } else {
                edgeSourceID = viewModel.selectedNodeIDs.first
                showingEdgeCreator = true
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
    }
}

// MARK: - Custom Node View (dispatcher)

/// Dispatches to the appropriate shared UML node view based on the node's content.
struct CustomNodeView: View {
    let node: CustomDiagramNode
    let isSelected: Bool
    /// Explicit size for resizable container nodes. `nil` for auto-sized nodes.
    var size: CGSize? = nil

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
            UMLContainerNodeView(name: node.name, stereotype: "package", style: .package, isSelected: isSelected, size: size)
        case .boundary:
            UMLContainerNodeView(name: node.name, stereotype: "boundary", style: .boundary, isSelected: isSelected, size: size)
        case .subsystem:
            UMLContainerNodeView(name: node.name, stereotype: "subsystem", style: .subsystem, isSelected: isSelected, size: size)
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

// MARK: - Custom Node Editor Sheet

struct CustomNodeEditorSheet: View {
    @ObservedObject var viewModel: CustomDiagramEditorViewModel
    let nodeID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedKind: DiagramElementKind = .type(.class)
    @State private var noteText: String = ""
    @State private var newPropertyText = ""
    @State private var newMethodText = ""

    private var node: CustomDiagramNode? {
        viewModel.nodes.first(where: { $0.id == nodeID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Node").font(.title2).bold()

            Form {
                Section("General") {
                    TextField("Name", text: $name)
                    Picker("Kind", selection: $selectedKind) {
                        ForEach(DiagramElementKind.CatalogGroup.allCases, id: \.rawValue) { group in
                            Section(group.rawValue) {
                                ForEach(DiagramElementKind.catalogItems(in: group)) { elementKind in
                                    Text(elementKind.displayName).tag(elementKind)
                                }
                            }
                        }
                    }
                }

                // Type-specific sections
                if case .type = selectedKind {
                    Section("Properties") {
                        if let node, case .type(let content) = node.content {
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
                        }
                        HStack {
                            TextField("e.g. name: String", text: $newPropertyText)
                                .font(.system(size: 12, design: .monospaced))
                            Button {
                                viewModel.addPropertyFromText(to: nodeID, text: newPropertyText)
                                newPropertyText = ""
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            .disabled(newPropertyText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }

                    Section("Methods") {
                        if let node, case .type(let content) = node.content {
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
                        }
                        HStack {
                            TextField("e.g. doWork(input: Int): String", text: $newMethodText)
                                .font(.system(size: 12, design: .monospaced))
                            Button {
                                viewModel.addMethodFromText(to: nodeID, text: newMethodText)
                                newMethodText = ""
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            .disabled(newMethodText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }

                // Note-specific section
                if case .note = selectedKind {
                    Section("Note Text") {
                        TextEditor(text: $noteText)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 80)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Done") {
                    viewModel.updateNode(nodeID, name: name, kind: selectedKind)
                    if case .note = selectedKind {
                        viewModel.updateNoteText(nodeID, text: noteText)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 500, height: 520)
        .onAppear {
            if let node {
                name = node.name
                selectedKind = node.content.elementKind
                if case .note(let text) = node.content {
                    noteText = text
                }
            }
        }
    }
}

// MARK: - Custom Edge Creator Sheet

struct CustomEdgeCreatorSheet: View {
    @ObservedObject var viewModel: CustomDiagramEditorViewModel
    let sourceNodeID: UUID?
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSourceID: UUID? = nil
    @State private var selectedTargetID: UUID? = nil
    @State private var selectedKind: Relationship.Kind = .association

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Relationship").font(.title2).bold()

            Form {
                Picker("Source", selection: $selectedSourceID) {
                    Text("Select…").tag(nil as UUID?)
                    ForEach(viewModel.nodes) { node in
                        Text(node.name).tag(node.id as UUID?)
                    }
                }

                Picker("Target", selection: $selectedTargetID) {
                    Text("Select…").tag(nil as UUID?)
                    ForEach(viewModel.nodes) { node in
                        Text(node.name).tag(node.id as UUID?)
                    }
                }

                Picker("Kind", selection: $selectedKind) {
                    Text("Inheritance").tag(Relationship.Kind.inheritance)
                    Text("Conformance").tag(Relationship.Kind.conformance)
                    Text("Composition").tag(Relationship.Kind.composition)
                    Text("Aggregation").tag(Relationship.Kind.aggregation)
                    Text("Association").tag(Relationship.Kind.association)
                    Text("Dependency").tag(Relationship.Kind.dependency)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    if let src = selectedSourceID, let tgt = selectedTargetID {
                        viewModel.addEdge(from: src, to: tgt, kind: selectedKind)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedSourceID == nil || selectedTargetID == nil)
            }
        }
        .padding()
        .frame(width: 400, height: 340)
        .onAppear {
            selectedSourceID = sourceNodeID
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
