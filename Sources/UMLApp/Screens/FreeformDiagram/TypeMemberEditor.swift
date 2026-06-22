import Foundation

/// Type-member editing for the freeform diagram: properties and methods on `.type` nodes, plus the
/// inline text editing (node name, member text, note text) that the inspector drives keystroke by
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

    func addProperty(to nodeID: String, name: String, type: String) {
        context.updateTypeContent(nodeID) { $0.properties.append(.init(name: name, type: type)) }
    }

    /// Parse a single string like "name: String" into a property and add it.
    func addPropertyFromText(to nodeID: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        context.updateTypeContent(nodeID) { $0.properties.append(.init(propertyText: trimmed)) }
    }

    func addMethod(to nodeID: String, name: String, returnType: String, parameters: String) {
        context.updateTypeContent(nodeID) {
            $0.methods.append(.init(name: name, type: returnType, parameters: parameters))
        }
    }

    /// Parse a single string like "doWork(input: Int): String" into a method and add it.
    func addMethodFromText(to nodeID: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        context.updateTypeContent(nodeID) { $0.methods.append(.init(methodText: trimmed)) }
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

    func updatePropertyText(_ nodeID: String, memberID: UUID, text: String) {
        // Reuse the shared property parser; only overwrite the type when the text actually
        // carries one (no colon ⇒ keep the existing type while the user is still typing).
        let parsed = FreeformDiagram.Node.Member(propertyText: text)
        context.updateTypeContent(nodeID) { content in
            guard let i = content.properties.firstIndex(where: { $0.id == memberID }) else { return }
            content.properties[i].name = parsed.name
            if text.contains(":") { content.properties[i].type = parsed.type }
        }
    }

    func updateMethodText(_ nodeID: String, memberID: UUID, text: String) {
        // Reuse the shared method parser; only overwrite the parameters / return type when the
        // text carries them, so a half-typed signature doesn't wipe the other fields.
        let parsed = FreeformDiagram.Node.Member(methodText: text)
        context.updateTypeContent(nodeID) { content in
            guard let i = content.methods.firstIndex(where: { $0.id == memberID }) else { return }
            content.methods[i].name = parsed.name
            if text.contains("(") { content.methods[i].parameters = parsed.parameters }
            if text.contains(":") { content.methods[i].type = parsed.type }
        }
    }

    func addInlineProperty(to nodeID: String) {
        context.updateTypeContent(nodeID) { $0.properties.append(.init(name: "newProperty", type: "Type")) }
    }

    func addInlineMethod(to nodeID: String) {
        context.updateTypeContent(nodeID) { $0.methods.append(.init(name: "newMethod", type: "Void")) }
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
