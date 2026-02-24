import UMLCore

enum UMLMemberFormatting {

    static func formatProperty(_ member: Member) -> String {
        var result = accessSymbol(member.accessLevel)
        result += " "
        result += member.name
        if let type = member.type {
            result += ": " + typeRefString(type)
        }
        return result
    }

    static func formatMethod(_ member: Member) -> String {
        var result = accessSymbol(member.accessLevel)
        result += " "
        result += member.name

        let paramStr = member.parameters.map { p in
            var s = p.internalName
            if let t = p.type {
                s += ": " + typeRefString(t)
            }
            return s
        }.joined(separator: ", ")
        result += "(\(paramStr))"

        if let type = member.type {
            result += ": " + typeRefString(type)
        }
        return result
    }

    static func formatEnumCase(_ enumCase: EnumCase) -> String {
        var result = enumCase.name
        if let raw = enumCase.rawValue {
            result += " = " + raw
        }
        return result
    }

    static func typeRefString(_ ref: TypeReference) -> String {
        var s = ref.name
        if !ref.genericArguments.isEmpty {
            s += "<" + ref.genericArguments.map { typeRefString($0) }.joined(separator: ", ") + ">"
        }
        if ref.isOptional { s += "?" }
        if ref.isArray && !s.hasPrefix("Array") { s += "[]" }
        return s
    }

    static func stereotypeString(for kind: TypeKind) -> String? {
        switch kind {
        case .protocol, .interface: return "interface"
        case .enum: return "enumeration"
        case .struct: return "struct"
        case .typeAlias: return "typealias"
        case .object: return "object"
        case .annotation: return "annotation"
        case .module: return "module"
        case .trait: return "trait"
        case .record: return "record"
        case .class, .extension: return nil
        }
    }

    private static func accessSymbol(_ level: AccessLevel?) -> String {
        level?.umlSymbol ?? "~"
    }
}
