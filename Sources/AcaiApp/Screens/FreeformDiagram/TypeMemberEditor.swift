import Foundation
import AcaiCore

extension FreeformDiagram.Node.Member {
    /// A copy with the name/type trimmed and the legacy `parameters` string cleared (structured
    /// editing always writes `structuredParameters` instead), or `nil` if the trimmed name is
    /// blank. Used by `TypeMemberEditor` to commit an add/edit draft.
    fileprivate func trimmedForCommit() -> Self? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return nil }
        var result = self
        result.name = trimmedName
        result.type = type.trimmingCharacters(in: .whitespaces)
        result.parameters = ""
        return result
    }
}

/// Type-member editing for the freeform diagram: adding/removing properties and methods on `.type`
/// nodes, plus the inline text editing (node name, note text) that the inspector drives keystroke by
/// keystroke. Consecutive keystrokes in one field coalesce into a single undo step.
@MainActor
final class TypeMemberEditor {
    private unowned let context: any FreeformEditingContext

    init(context: any FreeformEditingContext) {
        self.context = context
    }

    /// Coalescing keys for runs of consecutive text edits that should undo as a single step.
    private enum TextEditField: Hashable {
        case name(String)
        case note(String)
    }

    /// Appends a property built from `draft`'s name/type/access/static/abstract fields (its `id`
    /// and legacy `parameters` string are ignored). No-op if the name is blank.
    func addProperty(to nodeID: String, draft: FreeformDiagram.Node.Member) {
        guard let trimmed = draft.trimmedForCommit() else { return }
        context.updateTypeContent(nodeID) { content in
            content.properties.append(trimmed)
        }
    }

    func updateProperty(in nodeID: String, memberID: UUID, draft: FreeformDiagram.Node.Member) {
        guard let trimmed = draft.trimmedForCommit() else { return }
        context.updateTypeContent(nodeID) { content in
            guard let idx = content.properties.firstIndex(where: { $0.id == memberID }) else { return }
            content.properties[idx] = trimmed
            content.properties[idx].id = memberID
        }
    }

    /// Appends a method built from `draft`'s name/return type/parameters/access/static/abstract
    /// fields (its `id` is ignored). No-op if the name is blank.
    func addMethod(to nodeID: String, draft: FreeformDiagram.Node.Member) {
        guard let trimmed = draft.trimmedForCommit() else { return }
        context.updateTypeContent(nodeID) { content in
            content.methods.append(trimmed)
        }
    }

    func updateMethod(in nodeID: String, memberID: UUID, draft: FreeformDiagram.Node.Member) {
        guard let trimmed = draft.trimmedForCommit() else { return }
        context.updateTypeContent(nodeID) { content in
            guard let idx = content.methods.firstIndex(where: { $0.id == memberID }) else { return }
            content.methods[idx] = trimmed
            content.methods[idx].id = memberID
        }
    }

    func removeProperty(from nodeID: String, memberID: UUID) {
        context.updateTypeContent(nodeID) { $0.properties.removeAll { $0.id == memberID } }
    }

    func removeMethod(from nodeID: String, memberID: UUID) {
        context.updateTypeContent(nodeID) { $0.methods.removeAll { $0.id == memberID } }
    }

    // MARK: - Inline Editing

    func updateNodeName(_ nodeID: String, name: String) {
        guard let idx = context.nodes.firstIndex(where: { $0.id == nodeID }),
              context.nodes[idx].name != name else { return }
        // Coalesce consecutive keystrokes in the same name field into one undo step.
        context.recordUndo(coalescingKey: TextEditField.name(nodeID))
        context.nodes[idx].name = name
        context.save()
    }

    /// Update the free-form text of a note node.
    func updateNoteText(_ nodeID: String, text: String) {
        guard let idx = context.nodes.firstIndex(where: { $0.id == nodeID }),
              case .note(let existing) = context.nodes[idx].content, existing != text else { return }
        // Coalesce consecutive keystrokes in the same note field into one undo step.
        context.recordUndo(coalescingKey: TextEditField.note(nodeID))
        context.nodes[idx].content = .note(text: text)
        context.save()
    }
}
