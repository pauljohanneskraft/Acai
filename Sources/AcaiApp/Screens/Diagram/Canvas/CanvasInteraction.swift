import CoreGraphics
import SwiftUI

/// The node-interaction surface shared canvas primitives need, so diagram views can share
/// pan/zoom, drag, resize, marquee selection and undo/redo instead of each reimplementing them.
/// Node identity is `String` everywhere (the freeform diagram's ids are `UUID().uuidString`), so
/// this protocol needs no `associatedtype`.
@MainActor
protocol CanvasInteraction: ObservableObject, DiagramHistoryHosting {
    var selectedNodeIDs: Set<String> { get set }

    /// True while the touch-only "Select" toolbar mode is active: on iOS/iPadOS, where there's no
    /// Cmd-click, tapping a node while this is `true` adds/removes it from the selection instead
    /// of replacing it. Unused on macOS. A protocol requirement (not an extension default)
    /// because it's `@Published` per conformer.
    var isMultiSelectActive: Bool { get set }

    var allNodeIDs: [String] { get }

    /// Center position in canvas coordinates, or `nil` if unknown.
    func nodePosition(_ id: String) -> CGPoint?

    /// Move a node's center to `position`.
    func moveNode(_ id: String, to position: CGPoint)

    /// The size used for hit-testing, edges and resize handles (user-resized > measured > estimated).
    func effectiveSize(for id: String) -> CGSize

    /// Callers clamp to a sensible minimum.
    func resizeNode(_ id: String, width: CGFloat, height: CGFloat)

    func selectNode(_ id: String, extending: Bool)

    /// Selects nodes by center point inside `rect`, not by bounding-box overlap.
    func selectNodes(in rect: CGRect)

    func clearSelection()

    func selectAll()

    /// Hook invoked whenever the node selection is *replaced* (not extended), so a model with a
    /// secondary selection (e.g. a selected edge) can clear it. A protocol requirement — not just
    /// an extension method — so an override is dynamically dispatched from the default
    /// `selectNode`/`selectNodes`/`clearSelection`/`selectAll`.
    func selectionWillReplace()
}

extension CanvasInteraction {
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

    func nodeRect(_ id: String) -> CGRect? {
        guard let pos = nodePosition(id) else { return nil }
        let size = effectiveSize(for: id)
        return CGRect(x: pos.x - size.width / 2, y: pos.y - size.height / 2,
                      width: size.width, height: size.height)
    }
}

/// A `CanvasInteraction` whose nodes are **fixed-size, drag-only** and laid out by a diagram layout
/// model — the shape every generated movement-only diagram (sequence, state, package, call graph)
/// shares. A conformer provides just the layout frames, the node id list, and a fallback size;
/// this refinement supplies the entire movement + undo surface on top.
@MainActor
protocol LayoutBackedCanvas: CanvasInteraction where Snapshot == [String: CGPoint] {
    /// The undoable state.
    var positionOverrides: [String: CGPoint] { get set }

    func nodeFrame(_ id: String) -> CGRect?

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
/// re-center action shared across diagram types.
@MainActor
struct FitToView {
    /// `rect` resolves each node's rect; `nil` skips a node without one.
    let nodeIDs: [String]
    let rect: (String) -> CGRect?
    var viewport: CGSize = CGSize(width: 900, height: 600)
    var padding: CGFloat = 60
    var maxScale: CGFloat = 1.2
    var minScale: CGFloat = 0.2

    /// `nil` when no node has a rect to frame.
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
