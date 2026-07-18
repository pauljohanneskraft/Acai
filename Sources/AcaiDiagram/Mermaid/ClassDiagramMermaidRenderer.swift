import AcaiCore

/// Renders a `CodeArtifact` as a Mermaid `classDiagram`.
///
/// Mirrors `ClassDiagramDOTRenderer`: it builds the same `ClassDiagram` model and honours the
/// member/visibility/relationship options, but emits Mermaid instead of DOT so the
/// result embeds directly in Markdown.
public struct ClassDiagramMermaidRenderer: MermaidRenderer {
    private let options: ClassDiagramOptions

    public var theme: DiagramTheme? { options.theme }

    public init(options: ClassDiagramOptions) {
        self.options = options
    }

    /// Builds the `ClassDiagram` model from `artifact`, then renders it.
    public func generate(from artifact: CodeArtifact) -> String {
        generate(from: ClassDiagramBuilder(options: options).build(from: artifact))
    }

    /// Renders a pre-built `ClassDiagram` model (built once via `CodeArtifact.classDiagram`).
    public func generate(from enriched: ClassDiagram) -> String {
        var lines: [String] = themePreamble
        lines.append("classDiagram")
        var allocator = MermaidIDAllocator()
        var idMap: [String: String] = [:]
        let types = enriched.types + (options.showExternalTypes ? enriched.externalTypes : [])
        // A per-node delta override fills the node via a trailing `style` directive; gated on the
        // closure so non-delta output is byte-for-byte unchanged.
        var nodeStyles: [String] = []
        for type in types {
            let safe = allocator.id(for: type.id)
            idMap[type.id] = safe
            lines.append(contentsOf: renderClass(type, safeID: safe))
            if let color = options.nodeColorOverride?(type) {
                nodeStyles.append("    style \(safe) stroke:\(color),stroke-width:3px")
            }
        }
        lines.append(contentsOf: nodeStyles)

        // Mermaid's `classDiagram` has no per-link colouring — `linkStyle` is a flowchart-only
        // directive and is rejected inside a `classDiagram` block — so a delta `edgeColorOverride`
        // cannot be honoured here and relationships render uncolored. Node tinting via the `style`
        // directive above is supported and retained.
        for rel in enriched.relationships where options.includedRelationshipKinds.contains(rel.kind) {
            guard let line = renderRelationship(rel, idMap: idMap) else { continue }
            lines.append(line)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Class rendering

    private func renderClass(_ type: TypeDeclaration, safeID: String) -> [String] {
        let config = options.languages.configuration(for: type)
        let header = "    class \(safeID)[\"\(displayName(for: type).mermaidLabelEscaped)\"]"

        var body: [String] = []
        if let stereotype = stereotypeString(for: type, config: config) {
            body.append("        <<\(stereotype)>>")
        }
        if options.showMembers {
            let (properties, methods) = type.partitionedMembers(visibleAtLeast: options.minimumAccessLevel)
            body += properties.map { "        " + memberLine($0, config: config) }
            body += methods.map { "        " + memberLine($0, config: config) }
            body += type.enumCases.map { "        \($0.name)" }
        }

        guard !body.isEmpty else { return [header] }
        return [header + " {"] + body + ["    }"]
    }

    private func displayName(for type: TypeDeclaration) -> String {
        guard options.showGenericParameters, !type.genericParameters.isEmpty else { return type.name }
        return type.name + "<" + type.genericParameters.map(\.name).joined(separator: ", ") + ">"
    }

    private func memberLine(_ member: Member, config: LanguageConfiguration) -> String {
        var line = ""
        if options.showAccessLevelSymbols {
            line += member.accessLevel.umlSymbol
        }
        line += member.name

        if member.isMethod {
            let params = member.parameters.map { parameter -> String in
                guard options.showMemberTypes, let type = parameter.type else { return parameter.internalName }
                return "\(parameter.internalName) \(typeString(type, config: config))"
            }.joined(separator: ", ")
            line += "(\(params))"
            if options.showMemberTypes, let returnType = member.type {
                line += " \(typeString(returnType, config: config))"
            }
        } else if options.showMemberTypes, let type = member.type {
            line += " \(typeString(type, config: config))"
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

    private func stereotypeString(for type: TypeDeclaration, config: LanguageConfiguration) -> String? {
        type.stereotype(
            annotationStereotypes: options.showAnnotationStereotypes ? config.annotationStereotypes : [:]
        )
    }

    // MARK: - Helpers

    /// The `Name<Args>?[]` display string from the shared `TypeReference` formatter, with `<>`
    /// escaped for Mermaid. Shared so DOT, Mermaid, and the app canvas stay in sync.
    private func typeString(_ ref: TypeReference, config: LanguageConfiguration) -> String {
        ref.umlDisplayString(collectionTypeNames: config.collectionTypeNames).mermaidGenerics
    }

}
