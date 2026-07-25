import CoreGraphics
import SwiftUI

/// The node-interaction surface the shared canvas primitives need, so the class, sequence and
/// freeform diagram views can share pan/zoom, drag, resize, marquee selection, measurement and
/// undo/redo instead of each reimplementing them.
///
/// Node identity is `String` everywhere (the freeform diagram's ids are `UUID().uuidString`), so
/// this protocol needs no `associatedtype`; the shared views stay generic over a concrete
/// `Model: CanvasInteraction`. It refines `DiagramHistoryHosting` (undo/redo) and
/// `ObservableObject` (so the shared views observe changes).
@MainActor
protocol CanvasInteraction: ObservableObject, DiagramHistoryHosting {
    /// The currently selected node ids.
    var selectedNodeIDs: Set<String> { get set }

    /// True while the touch-only "Select" toolbar mode is active (see `CanvasNodeGestures.swift`):
    /// on iOS/iPadOS, where there's no Cmd-click to extend a selection, tapping a node while this is
    /// `true` adds/removes it from `selectedNodeIDs` instead of replacing the selection outright.
    /// Unused on macOS, which keeps Cmd-click. A protocol requirement (not an extension default)
    /// because it's `@Published` storage on each conformer, driving the toolbar toggle's own view.
    var isMultiSelectActive: Bool { get set }

    /// Every selectable node's id, in the model's own order. Drives `selectAll` and marquee
    /// selection so those don't need a per-model reimplementation.
    var allNodeIDs: [String] { get }

    /// The center position of a node in canvas coordinates, or `nil` if unknown.
    func nodePosition(_ id: String) -> CGPoint?

    /// Move a node's center to a new canvas position.
    func moveNode(_ id: String, to position: CGPoint)

    /// The size used for hit-testing, edges and resize handles (user-resized > measured > estimated).
    func effectiveSize(for id: String) -> CGSize

    /// Resize a node (callers clamp to a sensible minimum).
    func resizeNode(_ id: String, width: CGFloat, height: CGFloat)

    /// Select a single node, optionally extending the current selection.
    func selectNode(_ id: String, extending: Bool)

    /// Replace the selection with the nodes whose center falls inside `rect`.
    func selectNodes(in rect: CGRect)

    /// Clear the selection.
    func clearSelection()

    /// Select every node.
    func selectAll()

    /// Hook invoked by the shared selection defaults whenever the node selection is *replaced*
    /// (not extended), so a model with a secondary selection (e.g. a selected edge) can clear it.
    /// A protocol requirement — not just an extension method — so the conformer's override is
    /// dynamically dispatched from the default `selectNode`/`selectNodes`/`clearSelection`/`selectAll`.
    func selectionWillReplace()
}

// Shared selection behavior. These are protocol *requirements* with defaults so a model can drop
// the boilerplate (every model selected identically), while a model that needs different behavior
// — e.g. `FreeformDiagramViewModel` also clearing its selected edge — can still override and have
// the override dispatched through generic `Model: CanvasInteraction` canvas code.
extension CanvasInteraction {
    /// Hook for a model with a secondary selection (e.g. `FreeformDiagramViewModel`'s selected
    /// edge) to clear it whenever the node selection is *replaced* (not extended). Default: a
    /// model with no secondary selection has nothing to clear. This keeps the "also drop the
    /// edge" rule in one place instead of bolted onto each selection method.
    func selectionWillReplace() {}

    func selectNode(_ id: String, extending: Bool) {
        if extending {
            if selectedNodeIDs.contains(id) {
                selectedNodeIDs.remove(id)
            } else {
                selectedNodeIDs.insert(id)
            }
        } else {
            selectionWillReplace()
            selectedNodeIDs = [id]
        }
    }

    /// Marquee selection: every node whose center (`nodePosition`) falls inside `rect`.
    func selectNodes(in rect: CGRect) {
        selectionWillReplace()
        selectedNodeIDs = Set(allNodeIDs.filter { id in
            guard let pos = nodePosition(id) else { return false }
            return rect.contains(pos)
        })
    }

    func clearSelection() {
        selectionWillReplace()
        selectedNodeIDs.removeAll()
    }

    func selectAll() {
        selectionWillReplace()
        selectedNodeIDs = Set(allNodeIDs)
    }

    /// The bounding rect of a node from its center position and effective size.
    func nodeRect(_ id: String) -> CGRect? {
        guard let pos = nodePosition(id) else { return nil }
        let size = effectiveSize(for: id)
        return CGRect(x: pos.x - size.width / 2, y: pos.y - size.height / 2,
                      width: size.width, height: size.height)
    }
}

/// A `CanvasInteraction` whose nodes are **fixed-size, drag-only** and laid out by a diagram layout
/// model — the shape every generated movement-only diagram (sequence, state, package, call graph)
/// shares. The only editable state is a `[String: CGPoint]` of per-node centre overrides, so this
/// refinement supplies the entire movement + undo surface; a conformer provides just the layout
/// frames, the node id list, and a fallback size.
@MainActor
protocol LayoutBackedCanvas: CanvasInteraction where Snapshot == [String: CGPoint] {
    /// Per-node centre overrides, keyed by node id. The undoable state.
    var positionOverrides: [String: CGPoint] { get set }

    /// The laid-out frame of a node, or `nil` if the layout doesn't place it.
    func nodeFrame(_ id: String) -> CGRect?

    /// Size used when a node has no laid-out frame yet.
    var defaultNodeSize: CGSize { get }
}

extension LayoutBackedCanvas {
    /// Undoable state is just the overrides; the diagram itself tracks the code.
    var historySnapshot: [String: CGPoint] {
        get { positionOverrides }
        set { positionOverrides = newValue }
    }

    func nodePosition(_ id: String) -> CGPoint? {
        guard let frame = nodeFrame(id) else { return nil }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    func moveNode(_ id: String, to position: CGPoint) {
        positionOverrides[id] = position
    }

    func effectiveSize(for id: String) -> CGSize {
        nodeFrame(id)?.size ?? defaultNodeSize
    }

    /// These nodes are fixed-size; resizing is a no-op.
    func resizeNode(_ id: String, width: CGFloat, height: CGFloat) {}
}

/// Computes a canvas scale + offset that fits all node rects within `viewport` — the "fit to view" /
/// re-center action shared across diagram types. A value you instantiate with the nodes to frame and
/// ask for its ``transform`` (behaviour on a value, not a free function).
@MainActor
struct FitToView {
    /// The nodes to frame, and how to resolve each one's rect (`nil` skips a node without a rect).
    let nodeIDs: [String]
    let rect: (String) -> CGRect?
    var viewport: CGSize = CGSize(width: 900, height: 600)
    var padding: CGFloat = 60
    var maxScale: CGFloat = 1.2
    var minScale: CGFloat = 0.2

    /// The scale + offset that centres and fits the node rects in `viewport`, or `nil` when no node
    /// has a rect to frame.
    var transform: (scale: CGFloat, offset: CGPoint)? {
        let rects = nodeIDs.compactMap(rect)
        guard let first = rects.first else { return nil }
        let bounds = rects.dropFirst().reduce(first) { $0.union($1) }
        let scaleX = (viewport.width - padding * 2) / max(bounds.width, 1)
        let scaleY = (viewport.height - padding * 2) / max(bounds.height, 1)
        let scale = max(min(min(scaleX, scaleY), maxScale), minScale)
        let offset = CGPoint(
            x: (viewport.width - bounds.width * scale) / 2 - bounds.minX * scale,
            y: (viewport.height - bounds.height * scale) / 2 - bounds.minY * scale
        )
        return (scale, offset)
    }
}
