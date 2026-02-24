import UMLCore

/// Renders `TypeDeclaration` values as DOT node definitions with HTML table labels.
struct DOTNodeRenderer {
    let options: DiagramOptions

    func render(types: [TypeDeclaration]) -> String {
        types.map { render($0) }.joined()
    }

    func render(_ type: TypeDeclaration) -> String {
        let nodeId = type.id.dotNodeID
        let label = buildHTMLLabel(for: type)
        return "  \(nodeId) [label=<\(label)>];\n"
    }

    // MARK: - HTML label

    private func buildHTMLLabel(for type: TypeDeclaration) -> String {
        let fill = options.theme.nodeFillColor
        let border = options.theme.nodeBorderColor
        let font = options.theme.fontColor
        let fontSize = options.fontSize

        var html = "<TABLE BORDER=\"1\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"4\" "
        html += "BGCOLOR=\"\(fill)\" COLOR=\"\(border)\">"

        // Header: stereotype + name
        html += "<TR><TD ALIGN=\"CENTER\">"
        if let stereotype = stereotypeString(for: type.kind) {
            html += "<FONT POINT-SIZE=\"\(fontSize - 2)\" COLOR=\"\(font)\">"
            html += "&lt;&lt;\(stereotype)&gt;&gt;</FONT><BR/>"
        }
        html += "<B><FONT COLOR=\"\(font)\">"
        html += type.name.dotHTMLEscaped
        if options.showGenericParameters && !type.genericParameters.isEmpty {
            html += "&lt;\(type.genericParameters.map(\.name).joined(separator: ", "))&gt;"
        }
        html += "</FONT></B>"
        html += "</TD></TR>"

        guard options.showMembers else {
            html += "</TABLE>"
            return html
        }

        let properties = filteredMembers(type.members.filter { isProperty($0) })
        let methods = filteredMembers(type.members.filter { isMethod($0) })

        // Properties compartment
        html += "<HR/><TR><TD ALIGN=\"LEFT\">"
        if properties.isEmpty {
            html += "<FONT COLOR=\"\(font)\"> </FONT>"
        } else {
            html += properties.map { renderMember($0) }.joined(separator: "<BR ALIGN=\"LEFT\"/>")
            html += "<BR ALIGN=\"LEFT\"/>"
        }
        html += "</TD></TR>"

        // Methods compartment
        html += "<HR/><TR><TD ALIGN=\"LEFT\">"
        if methods.isEmpty {
            html += "<FONT COLOR=\"\(font)\"> </FONT>"
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

    // MARK: - Member rendering

    private func renderMember(_ member: Member) -> String {
        let font = options.theme.fontColor
        var result = "<FONT COLOR=\"\(font)\">"
        if options.showAccessLevelSymbols, let access = member.accessLevel {
            result += access.umlSymbol.dotHTMLEscaped + " "
        }

        let isStatic = member.modifiers.contains(.static) || member.modifiers.contains(.class)
        let isAbstract = member.modifiers.contains(.abstract)

        if isStatic { result += "<U>" }
        if isAbstract { result += "<I>" }

        result += member.name.dotHTMLEscaped

        if isMethod(member) {
            let paramStr = member.parameters.map { p in
                var s = p.internalName.dotHTMLEscaped
                if options.showMemberTypes, let t = p.type {
                    s += ": " + typeRefString(t).dotHTMLEscaped
                }
                return s
            }.joined(separator: ", ")
            result += "(\(paramStr))"
        }

        if options.showMemberTypes, let type = member.type {
            result += ": " + typeRefString(type).dotHTMLEscaped
        }

        if isAbstract { result += "</I>" }
        if isStatic { result += "</U>" }
        result += "</FONT>"
        return result
    }

    private func renderEnumCase(_ enumCase: EnumCase) -> String {
        let font = options.theme.fontColor
        var result = "<FONT COLOR=\"\(font)\">"
        result += enumCase.name.dotHTMLEscaped
        if let raw = enumCase.rawValue {
            result += " = " + raw.dotHTMLEscaped
        }
        result += "</FONT>"
        return result
    }

    // MARK: - Helpers

    private func typeRefString(_ ref: TypeReference) -> String {
        var s = ref.name
        if !ref.genericArguments.isEmpty {
            s += "<" + ref.genericArguments.map { typeRefString($0) }.joined(separator: ", ") + ">"
        }
        if ref.isOptional { s += "?" }
        if ref.isArray && !s.hasPrefix("Array") { s += "[]" }
        return s
    }

    private func stereotypeString(for kind: TypeKind) -> String? {
        switch kind {
        case .protocol, .interface: return "interface"
        case .enum: return "enumeration"
        case .struct: return "struct"
        case .typeAlias: return "typealias"
        case .object: return "object"
        case .annotation: return "annotation"
        case .module: return "module"
        case .trait: return "trait"
        case .class, .extension: return nil
        case .record: return "record"
        }
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
            .protected: 3, .public: 4, .open: 5,
        ]
        guard let minRank = order[minAccess] else { return members }
        return members.filter { member in
            guard let access = member.accessLevel, let rank = order[access] else { return true }
            return rank >= minRank
        }
    }
}
