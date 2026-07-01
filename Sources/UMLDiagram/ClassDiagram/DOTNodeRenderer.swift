import UMLCore

/// Renders `TypeDeclaration` values as DOT node definitions with HTML table labels.
struct DOTNodeRenderer {
    let options: ClassDiagramOptions

    func render(types: [TypeDeclaration]) -> String {
        types.map { render($0) }.joined()
    }

    func render(_ type: TypeDeclaration) -> String {
        let nodeId = type.id.dotNodeID
        let label = buildHTMLLabel(for: type)
        return "  \(nodeId) [label=<\(label)>];\n"
    }

    /// Renders external (not-in-codebase) types as light gray placeholder nodes.
    func renderExternal(types: [TypeDeclaration]) -> String {
        guard !types.isEmpty else { return "" }
        var output = "  // External dependencies\n"
        for type in types {
            let nodeId = type.id.dotNodeID
            let label = buildExternalHTMLLabel(for: type)
            output += "  \(nodeId) [label=<\(label)>];\n"
        }
        return output
    }

    // MARK: - HTML label

    /// The opening `<TABLE …>` tag. A per-node delta override colours the node's *border* (not its
    /// fill) with a thicker border, so added/removed/changed nodes stand out while the body text and
    /// theme stay readable.
    private func tableOpenTag(for type: TypeDeclaration) -> String {
        let deltaBorder = options.nodeColorOverride?(type)
        var tag = "<TABLE BORDER=\"\(deltaBorder == nil ? 1 : 2)\""
            + " CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"4\""
        if let theme = options.theme {
            tag += " BGCOLOR=\"\(theme.nodeFillColor)\""
        }
        if let border = deltaBorder ?? options.theme?.nodeBorderColor {
            tag += " COLOR=\"\(border)\""
        }
        return tag + ">"
    }

    private func buildHTMLLabel(for type: TypeDeclaration) -> String {
        let font = options.theme?.fontColor
        let fontSize = options.fontSize
        var html = tableOpenTag(for: type)

        // Header: stereotype + name
        html += "<TR><TD ALIGN=\"CENTER\">"
        if let stereotype = stereotypeString(for: type) {
            html += "<FONT POINT-SIZE=\"\(fontSize - 2)\"\(colorAttr(font))>"
            html += "&lt;&lt;\(stereotype)&gt;&gt;</FONT><BR/>"
        }
        html += "<B>\(fontOpen(font))"
        html += type.name.dotHTMLEscaped
        if options.showGenericParameters && !type.genericParameters.isEmpty {
            html += "&lt;\(type.genericParameters.map(\.name).joined(separator: ", "))&gt;"
        }
        html += "\(fontClose(font))</B>"
        html += "</TD></TR>"

        guard options.showMembers else {
            html += "</TABLE>"
            return html
        }

        let (properties, methods) = type.partitionedMembers(visibleAtLeast: options.minimumAccessLevel)

        // Properties compartment
        html += "<HR/><TR><TD ALIGN=\"LEFT\">"
        if properties.isEmpty {
            html += "\(fontOpen(font)) \(fontClose(font))"
        } else {
            html += properties.map { renderMember($0) }.joined(separator: "<BR ALIGN=\"LEFT\"/>")
            html += "<BR ALIGN=\"LEFT\"/>"
        }
        html += "</TD></TR>"

        // Methods compartment
        html += "<HR/><TR><TD ALIGN=\"LEFT\">"
        if methods.isEmpty {
            html += "\(fontOpen(font)) \(fontClose(font))"
        } else {
            html += methods.map { renderMember($0) }.joined(separator: "<BR ALIGN=\"LEFT\"/>")
            html += "<BR ALIGN=\"LEFT\"/>"
        }
        html += "</TD></TR>"

        // Enum cases
        if !type.enumCases.isEmpty {
            html += "<HR/><TR><TD ALIGN=\"LEFT\">"
            html += type.enumCases.map { renderEnumCase($0) }.joined(separator: "<BR ALIGN=\"LEFT\"/>")
            html += "<BR ALIGN=\"LEFT\"/>"
            html += "</TD></TR>"
        }

        html += "</TABLE>"
        return html
    }

    /// Builds a simplified gray HTML table label for an external dependency type.
    private func buildExternalHTMLLabel(for type: TypeDeclaration) -> String {
        let fill = "#E8E8E8"
        let border = "#B0B0B0"
        let font = "#808080"
        let fontSize = options.fontSize

        var html = "<TABLE BORDER=\"1\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"4\" "
        html += "BGCOLOR=\"\(fill)\" COLOR=\"\(border)\">"

        // Header only: stereotype + name
        html += "<TR><TD ALIGN=\"CENTER\">"
        if let stereotype = stereotypeString(for: type) {
            html += "<FONT POINT-SIZE=\"\(fontSize - 2)\" COLOR=\"\(font)\">"
            html += "&lt;&lt;\(stereotype)&gt;&gt;</FONT><BR/>"
        }
        html += "<B><FONT COLOR=\"\(font)\">"
        html += type.name.dotHTMLEscaped
        html += "</FONT></B>"
        html += "</TD></TR>"
        html += "</TABLE>"
        return html
    }

    // MARK: - Member rendering

    private func renderMember(_ member: Member) -> String {
        let font = options.theme?.fontColor
        var result = fontOpen(font)
        if options.showAccessLevelSymbols {
            result += member.accessLevel.umlSymbol.dotHTMLEscaped + " "
        }

        let isStatic = member.modifiers.contains(.static) || member.modifiers.contains(.class)
        let isAbstract = member.modifiers.contains(.abstract)

        if isStatic { result += "<U>" }
        if isAbstract { result += "<I>" }

        result += member.name.dotHTMLEscaped

        if member.isMethod {
            let paramStr = member.parameters.map { p in
                var parameterString = p.internalName.dotHTMLEscaped
                if options.showMemberTypes, let parameterType = p.type {
                    parameterString += ": " + typeRefString(parameterType).dotHTMLEscaped
                }
                return parameterString
            }.joined(separator: ", ")
            result += "(\(paramStr))"
        }

        if options.showMemberTypes, let type = member.type {
            result += ": " + typeRefString(type).dotHTMLEscaped
        }

        if isAbstract { result += "</I>" }
        if isStatic { result += "</U>" }
        result += fontClose(font)
        return result
    }

    private func renderEnumCase(_ enumCase: EnumCase) -> String {
        let font = options.theme?.fontColor
        var result = fontOpen(font)
        result += enumCase.name.dotHTMLEscaped
        if let raw = enumCase.rawValue {
            result += " = " + raw.dotHTMLEscaped
        }
        result += fontClose(font)
        return result
    }

    // MARK: - Font color (structural when no theme)

    /// `COLOR="…"` attribute fragment for a `<FONT>` tag, or empty when unthemed.
    private func colorAttr(_ color: String?) -> String {
        color.map { " COLOR=\"\($0)\"" } ?? ""
    }

    /// Opening `<FONT COLOR="…">` when themed, else empty — so structural output carries no colour.
    private func fontOpen(_ color: String?) -> String {
        color.map { "<FONT COLOR=\"\($0)\">" } ?? ""
    }

    /// Matching `</FONT>` for ``fontOpen(_:)`` (empty when unthemed).
    private func fontClose(_ color: String?) -> String {
        color != nil ? "</FONT>" : ""
    }

    // MARK: - Helpers

    /// The `Name<Args>?[]` display string, using the shared `TypeReference` formatter so DOT,
    /// Mermaid, and the app canvas stay in sync. Caller HTML-escapes the result.
    private func typeRefString(_ ref: TypeReference) -> String {
        ref.umlDisplayString(collectionTypeNames: options.language.collectionTypeNames)
    }

    private func stereotypeString(for type: TypeDeclaration) -> String? {
        type.stereotype(
            annotationStereotypes: options.showAnnotationStereotypes ? options.language.annotationStereotypes : [:]
        )
    }

}
