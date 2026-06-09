import SwiftUI
import UMLCore
#if os(macOS)
import AppKit
#endif

// MARK: - Clipboard (Cut / Copy / Paste)

extension CustomDiagramViewModel {

    /// Internal clipboard representation.
    private struct ClipboardPayload: Codable {
        var nodes: [CustomDiagram.Node]
        var edges: [CustomDiagram.Edge]
    }

    private static var pasteboardType: String { "com.umlapp.diagram.nodes" }

    /// Copy the currently selected nodes (and edges between them) to the system clipboard.
    func copySelection() {
        guard !selectedNodeIDs.isEmpty else { return }
        let selectedNodes = nodes.filter { selectedNodeIDs.contains($0.id) }
        let selectedEdges = edges.filter {
            selectedNodeIDs.contains($0.sourceNodeID)
                && selectedNodeIDs.contains($0.targetNodeID)
        }
        let payload = ClipboardPayload(nodes: selectedNodes, edges: selectedEdges)
        guard let data = try? JSONEncoder().encode(payload) else { return }

        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .init(Self.pasteboardType))
        #endif
    }

    /// Cut: copy selection then delete.
    func cutSelection() {
        copySelection()
        recordUndo()
        let toRemove = selectedNodeIDs
        for id in toRemove {
            nodes.removeAll { $0.id == id }
            edges.removeAll { $0.sourceNodeID == id || $0.targetNodeID == id }
            selectedNodeIDs.remove(id)
        }
        // Connected edges may have been removed as a side-effect, so drop any stale edge selection.
        selectedEdgeID = nil
        save()
    }

    /// Paste from the system clipboard, offsetting positions so nodes don't overlap originals.
    func paste() {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        guard let data = pasteboard.data(forType: .init(Self.pasteboardType)),
              let payload = try? JSONDecoder().decode(ClipboardPayload.self, from: data) else { return }
        #else
        return
        #endif

        guard !payload.nodes.isEmpty else { return }

        recordUndo()

        // Build mapping from old IDs to new IDs.
        var idMapping: [UUID: UUID] = [:]
        for node in payload.nodes {
            idMapping[node.id] = UUID()
        }

        let offset: Double = 30.0
        var newSelection = Set<UUID>()

        for var node in payload.nodes {
            let newID = idMapping[node.id]!
            node.id = newID
            node.positionX += offset
            node.positionY += offset
            nodes.append(node)
            newSelection.insert(newID)
        }

        for var edge in payload.edges {
            guard let newSource = idMapping[edge.sourceNodeID],
                  let newTarget = idMapping[edge.targetNodeID] else { continue }
            edge.id = UUID()
            edge.sourceNodeID = newSource
            edge.targetNodeID = newTarget
            edges.append(edge)
        }

        selectedNodeIDs = newSelection
        selectedEdgeID = nil
        save()
    }

    /// Select all nodes.
    func selectAll() {
        selectedNodeIDs = Set(nodes.map(\.id))
        selectedEdgeID = nil
    }
}
