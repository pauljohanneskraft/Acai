import Foundation

// MARK: - Member CRUD & Inline Editing

extension FreeformDiagramViewModel {

    func addProperty(to nodeID: String, name: String, type: String) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeID }),
              case .type(var content) = nodes[idx].content else { return }
        recordUndo()
        content.properties.append(.init(name: name, type: type))
        nodes[idx].content = .type(content)
        save()
    }

    /// Parse a single string like "name: String" into a property and add it.
    func addPropertyFromText(to nodeID: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let parts = trimmed.split(separator: ":", maxSplits: 1)
        let name = parts.first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? trimmed
        let type = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
        addProperty(to: nodeID, name: name, type: type)
    }

    func addMethod(to nodeID: String, name: String, returnType: String, parameters: String) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeID }),
              case .type(var content) = nodes[idx].content else { return }
        recordUndo()
        content.methods.append(.init(name: name, type: returnType, parameters: parameters))
        nodes[idx].content = .type(content)
        save()
    }

    /// Parse a single string like "doWork(input: Int): String" into a method and add it.
    func addMethodFromText(to nodeID: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        var name = trimmed
        var params = ""
        var returnType = ""

        if let parenStart = trimmed.firstIndex(of: "("),
           let parenEnd = trimmed.firstIndex(of: ")") {
            name = String(trimmed[trimmed.startIndex..<parenStart])
                .trimmingCharacters(in: .whitespaces)
            params = String(trimmed[trimmed.index(after: parenStart)..<parenEnd])
            let afterParen = trimmed[trimmed.index(after: parenEnd)...]
            if let colonIdx = afterParen.firstIndex(of: ":") {
                returnType = String(
                    afterParen[afterParen.index(after: colonIdx)...]
                ).trimmingCharacters(in: .whitespaces)
            }
        } else if let colonIdx = trimmed.firstIndex(of: ":") {
            name = String(trimmed[trimmed.startIndex..<colonIdx])
                .trimmingCharacters(in: .whitespaces)
            returnType = String(trimmed[trimmed.index(after: colonIdx)...])
                .trimmingCharacters(in: .whitespaces)
        }

        addMethod(to: nodeID, name: name, returnType: returnType, parameters: params)
    }

    func removeProperty(from nodeID: String, memberID: UUID) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeID }),
              case .type(var content) = nodes[idx].content else { return }
        recordUndo()
        content.properties.removeAll { $0.id == memberID }
        nodes[idx].content = .type(content)
        save()
    }

    func removeMethod(from nodeID: String, memberID: UUID) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeID }),
              case .type(var content) = nodes[idx].content else { return }
        recordUndo()
        content.methods.removeAll { $0.id == memberID }
        nodes[idx].content = .type(content)
        save()
    }

    // MARK: - Inline Editing

    func updateNodeName(_ nodeID: String, name: String) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeID }), nodes[idx].name != name else { return }
        // Coalesce consecutive keystrokes in the same name field into one undo step.
        recordUndo(coalescingKey: TextEditField.name(nodeID))
        nodes[idx].name = name
        save()
    }

    func updatePropertyText(_ nodeID: String, memberID: UUID, text: String) {
        guard let nodeIndex = nodes.firstIndex(where: { $0.id == nodeID }),
              case .type(var content) = nodes[nodeIndex].content,
              let memberIndex = content.properties.firstIndex(where: { $0.id == memberID }) else { return }
        recordUndo()
        let parts = text.split(separator: ":", maxSplits: 1)
        content.properties[memberIndex].name = parts.first
            .map(String.init)?.trimmingCharacters(in: .whitespaces) ?? text
        if parts.count > 1 {
            content.properties[memberIndex].type = String(parts[1]).trimmingCharacters(in: .whitespaces)
        }
        nodes[nodeIndex].content = .type(content)
        save()
    }

    func updateMethodText(_ nodeID: String, memberID: UUID, text: String) {
        guard let nodeIndex = nodes.firstIndex(where: { $0.id == nodeID }),
              case .type(var content) = nodes[nodeIndex].content,
              let memberIndex = content.methods.firstIndex(where: { $0.id == memberID }) else { return }
        recordUndo()
        if let parenStart = text.firstIndex(of: "("),
           let parenEnd = text.firstIndex(of: ")") {
            content.methods[memberIndex].name = String(text[text.startIndex..<parenStart])
                .trimmingCharacters(in: .whitespaces)
            content.methods[memberIndex].parameters = String(text[text.index(after: parenStart)..<parenEnd])
            let afterParen = text[text.index(after: parenEnd)...]
            if let colonIdx = afterParen.firstIndex(of: ":") {
                content.methods[memberIndex].type = String(
                    afterParen[afterParen.index(after: colonIdx)...]
                ).trimmingCharacters(in: .whitespaces)
            }
        } else {
            content.methods[memberIndex].name = text
        }
        nodes[nodeIndex].content = .type(content)
        save()
    }

    func addInlineProperty(to nodeID: String) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeID }),
              case .type(var content) = nodes[idx].content else { return }
        recordUndo()
        content.properties.append(.init(name: "newProperty", type: "Type"))
        nodes[idx].content = .type(content)
        save()
    }

    func addInlineMethod(to nodeID: String) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeID }),
              case .type(var content) = nodes[idx].content else { return }
        recordUndo()
        content.methods.append(.init(name: "newMethod", type: "Void"))
        nodes[idx].content = .type(content)
        save()
    }

    /// Update the free-form text of a note node.
    func updateNoteText(_ nodeID: String, text: String) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeID }),
              case .note(let existing) = nodes[idx].content, existing != text else { return }
        // Coalesce consecutive keystrokes in the same note field into one undo step.
        recordUndo(coalescingKey: TextEditField.note(nodeID))
        nodes[idx].content = .note(text: text)
        save()
    }
}
