import UMLCore

/// Renders a `CodeArtifact` as a Mermaid `classDiagram`.
///
/// Mirrors `DOTGenerator`: it runs the same `ClassDiagramEnricher` and honours the
/// member/visibility/relationship options, but emits Mermaid instead of DOT so the
/// result embeds directly in Markdown.
public struct ClassDiagramMermaidRenderer: Sendable {
    private let options: ClassDiagramOptions

    public init(options: ClassDiagramOptions) {
        self.options = options
    }

    /// Builds the `ClassDiagram` model from `artifact`, then renders it.
    public func generate(from artifact: CodeArtifact) -> String {
        generate(from: artifact.classDiagram(options: options))
    }

    /// Renders a pre-built `ClassDiagram` model (built once via `CodeArtifact.classDiagram`).
    public func generate(from enriched: ClassDiagram) -> String {
        var lines: [String] = []
        if let theme = options.theme { lines.append(theme.mermaidInit()) }
        lines.append("classDiagram")
        var allocator = MermaidIDAllocator()
        var idMap: [String: String] = [:]
        let types = enriched.types + (options.showExternalTypes ? enriched.externalTypes : [])
        for type in types {
            let safe = allocator.id(for: type.id)
            idMap[type.id] = safe
            lines.append(contentsOf: renderClass(type, safeID: safe))
        }

        for rel in enriched.relationships where options.includedRelationshipKinds.contains(rel.kind) {
            guard let line = renderRelationship(rel, idMap: idMap) else { continue }
            lines.append(line)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Class rendering

    private func renderClass(_ type: TypeDeclaration, safeID: String) -> [String] {
        let header = "    class \(safeID)[\"\(displayName(for: type).mermaidLabelEscaped)\"]"

        var body: [String] = []
        if let stereotype = stereotypeString(for: type) {
            body.append("        <<\(stereotype)>>")
        }
        if options.showMembers {
            let properties = filteredMembers(type.members.filter(isProperty))
            let methods = filteredMembers(type.members.filter(isMethod))
            body += properties.map { "        " + memberLine($0) }
            body += methods.map { "        " + memberLine($0) }
            body += type.enumCases.map { "        \($0.name)" }
        }

        guard !body.isEmpty else { return [header] }
        return [header + " {"] + body + ["    }"]
    }

    private func displayName(for type: TypeDeclaration) -> String {
        guard options.showGenericParameters, !type.genericParameters.isEmpty else { return type.name }
        return type.name + "<" + type.genericParameters.map(\.name).joined(separator: ", ") + ">"
    }

    private func memberLine(_ member: Member) -> String {
        var line = ""
        if options.showAccessLevelSymbols, let access = member.accessLevel {
            line += access.umlSymbol
        }
        line += member.name

        if isMethod(member) {
            let params = member.parameters.map { parameter -> String in
                guard options.showMemberTypes, let type = parameter.type else { return parameter.internalName }
                return "\(parameter.internalName) \(typeString(type))"
            }.joined(separator: ", ")
            line += "(\(params))"
            if options.showMemberTypes, let returnType = member.type {
                line += " \(typeString(returnType))"
            }
        } else if options.showMemberTypes, let type = member.type {
            line += " \(typeString(type))"
        }

        if member.modifiers.contains(.static) || member.modifiers.contains(.class) {
            line += "$"
        } else if member.modifiers.contains(.abstract) {
            line += "*"
        }
        return line
    }

    // MARK: - Relationship rendering

    /// Maps a `Relationship` to a Mermaid class-diagram link, preserving the same
    /// whole/part and parent/child orientation the DOT renderer uses.
    private func renderRelationship(_ rel: Relationship, idMap: [String: String]) -> String? {
        guard let source = idMap[rel.source], let target = idMap[rel.target] else { return nil }
        // Source/target operands as Mermaid writes them: inheritance/conformance flip the
        // arrow so the supertype leads, so the multiplicity labels follow the same operands.
        let leadsWithTarget = rel.kind == .inheritance || rel.kind == .conformance
        let leadID = leadsWithTarget ? target : source
        let trailID = leadsWithTarget ? source : target
        let leadLabel = leadsWithTarget ? rel.targetLabel : rel.sourceLabel
        let trailLabel = leadsWithTarget ? rel.sourceLabel : rel.targetLabel

        let link = "\(operand(leadID, label: leadLabel))\(arrow(for: rel.kind))"
            + "\(operand(trailID, label: trailLabel, labelLeading: true))"
        guard let label = rel.label else { return "    \(link)" }
        return "    \(link) : \(label.mermaidTextEscaped)"
    }

    /// A relationship operand, optionally carrying a quoted multiplicity. Mermaid puts the
    /// cardinality between the class id and the link, so a trailing operand's label leads it.
    private func operand(_ id: String, label: String?, labelLeading: Bool = false) -> String {
        guard options.showMultiplicities, let label else { return id }
        let quoted = "\"\(label.mermaidTextEscaped)\""
        return labelLeading ? "\(quoted) \(id)" : "\(id) \(quoted)"
    }

    private func arrow(for kind: Relationship.Kind) -> String {
        switch kind {
        case .inheritance:
            " <|-- "
        case .conformance:
            " <|.. "
        case .composition, .nesting:
            " *-- "
        case .aggregation:
            " o-- "
        case .association:
            " --> "
        case .dependency:
            " ..> "
        case .extension:
            " ..|> "
        }
    }

    private func stereotypeString(for type: TypeDeclaration) -> String? {
        type.stereotype(
            annotationStereotypes: options.showAnnotationStereotypes ? options.language.annotationStereotypes : [:]
        )
    }

    // MARK: - Helpers

    private func typeString(_ ref: TypeReference) -> String {
        var result = ref.name
        if !ref.genericArguments.isEmpty {
            result += "<" + ref.genericArguments.map { typeString($0) }.joined(separator: ", ") + ">"
        }
        if ref.isOptional { result += "?" }
        if ref.isArray && !result.hasPrefix("Array") { result += "[]" }
        return result.mermaidGenerics
    }

    private func isProperty(_ member: Member) -> Bool {
        member.kind == .property || member.kind == .subscript
    }

    private func isMethod(_ member: Member) -> Bool {
        member.kind == .method || member.kind == .initializer || member.kind == .deinitializer
    }

    private func filteredMembers(_ members: [Member]) -> [Member] {
        guard let minAccess = options.minimumAccessLevel else { return members }
        let order: [AccessLevel: Int] = [
            .private: 0, .filePrivate: 1, .internal: 2, .packagePrivate: 2,
            .protected: 3, .public: 4, .open: 5
        ]
        guard let minRank = order[minAccess] else { return members }
        return members.filter { member in
            guard let access = member.accessLevel, let rank = order[access] else { return true }
            return rank >= minRank
        }
    }
}
