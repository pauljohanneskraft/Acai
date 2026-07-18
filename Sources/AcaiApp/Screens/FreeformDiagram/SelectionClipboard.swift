import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Cut / copy / paste for the freeform diagram's node-and-edge selection. Copy serialises the
/// selected nodes (and the edges between them) to the system pasteboard; paste re-materialises them
/// with fresh ids and a small offset so they don't land on top of the originals.
@MainActor
final class SelectionClipboard {
    private unowned let context: any FreeformEditingContext

    init(context: any FreeformEditingContext) {
        self.context = context
    }

    /// Internal clipboard representation.
    private struct ClipboardPayload: Codable {
        var nodes: [FreeformDiagram.Node]
        var edges: [FreeformDiagram.Edge]
    }

    private static var pasteboardType: String { "com.acai.diagram.nodes" }

    /// Copy the currently selected nodes (and edges between them) to the system clipboard.
    func copySelection() {
        guard !context.selectedNodeIDs.isEmpty else { return }
        let selectedNodes = context.nodes.filter { context.selectedNodeIDs.contains($0.id) }
        // Only edges with *both* endpoints selected are copied — a half-dangling edge has no second
        // endpoint to re-attach to on paste. (Cut still deletes edges merely *touching* the
        // selection, via `removeNodes`, because removing a node must remove its dangling edges.)
        let selectedEdges = context.edges.filter {
            context.selectedNodeIDs.contains($0.sourceNodeID)
                && context.selectedNodeIDs.contains($0.targetNodeID)
        }
        let payload = ClipboardPayload(nodes: selectedNodes, edges: selectedEdges)
        guard let data = try? JSONEncoder().encode(payload) else { return }

        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .init(Self.pasteboardType))
        #else
        UIPasteboard.general.setData(data, forPasteboardType: Self.pasteboardType)
        #endif
    }

    /// Cut: copy selection then delete.
    func cutSelection() {
        guard !context.selectedNodeIDs.isEmpty else { return }
        copySelection()
        context.recordUndo(coalescingKey: nil)
        context.removeNodes(context.selectedNodeIDs)
        // Connected edges may have been removed as a side-effect, so drop any stale edge selection.
        context.selectedEdgeID = nil
        context.save()
    }

    /// Paste from the system clipboard, offsetting positions so nodes don't overlap originals.
    func paste() {
        #if os(macOS)
        guard let data = NSPasteboard.general.data(forType: .init(Self.pasteboardType)),
              let payload = try? JSONDecoder().decode(ClipboardPayload.self, from: data) else { return }
        #else
        guard let data = UIPasteboard.general.data(forPasteboardType: Self.pasteboardType),
              let payload = try? JSONDecoder().decode(ClipboardPayload.self, from: data) else { return }
        #endif

        guard !payload.nodes.isEmpty else { return }

        context.recordUndo(coalescingKey: nil)

        // Build mapping from old IDs to new IDs.
        var idMapping: [String: String] = [:]
        for node in payload.nodes {
            idMapping[node.id] = UUID().uuidString
        }

        let offset: Double = 30.0
        var newSelection = Set<String>()

        for var node in payload.nodes {
            guard let newID = idMapping[node.id] else { continue }
            node.id = newID
            node.positionX += offset
            node.positionY += offset
            context.nodes.append(node)
            newSelection.insert(newID)
        }

        for var edge in payload.edges {
            guard let newSource = idMapping[edge.sourceNodeID],
                  let newTarget = idMapping[edge.targetNodeID] else { continue }
            edge.id = UUID().uuidString
            edge.sourceNodeID = newSource
            edge.targetNodeID = newTarget
            context.edges.append(edge)
        }

        context.selectedNodeIDs = newSelection
        context.selectedEdgeID = nil
        context.save()
    }
}
