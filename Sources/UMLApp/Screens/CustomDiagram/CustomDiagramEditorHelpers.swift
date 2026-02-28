import SwiftUI
import UMLCore

// MARK: - Canvas Right-Click Tracker

#if os(macOS)
/// An invisible NSView overlay that captures right-click events and records the
/// click location in canvas coordinates before the SwiftUI context menu appears.
struct CanvasRightClickTracker: NSViewRepresentable {
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
struct CanvasRightClickTracker: View {
    @Binding var canvasPoint: CGPoint
    let scale: CGFloat
    let offset: CGPoint
    var body: some View { Color.clear.allowsHitTesting(false) }
}
#endif

// MARK: - Resize State

struct ResizeState {
    let startSize: CGSize
    let startPosition: CGPoint
}

// MARK: - Custom Node View (dispatcher)

/// Dispatches to the appropriate shared UML node view based on the node's content.
struct CustomNodeView: View {
    let node: CustomDiagram.Node
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
                systemImage: node.content.kind.systemImage,
                isSelected: isSelected
            )
        }
    }
}

// MARK: - DiagramEdge convenience init for custom diagrams.

extension GeneratedDiagramEdge {
    init(id: String, sourceID: String, targetID: String, kind: Relationship.Kind) {
        self.id = id
        self.sourceID = sourceID
        self.targetID = targetID
        self.kind = kind
    }
}
