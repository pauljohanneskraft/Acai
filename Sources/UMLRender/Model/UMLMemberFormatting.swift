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
            var parameterString = p.internalName
            if let parameterType = p.type {
                parameterString += ": " + typeRefString(parameterType)
            }
            return parameterString
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
        var typeString = ref.name
        if !ref.genericArguments.isEmpty {
            typeString += "<" + ref.genericArguments.map { typeRefString($0) }.joined(separator: ", ") + ">"
        }
        if ref.isOptional { typeString += "?" }
        if ref.isArray && !typeString.hasPrefix("Array") { typeString += "[]" }
        return typeString
    }

    static func stereotypeString(for kind: TypeKind) -> String? {
        kind.stereotypeString
    }

    private static func accessSymbol(_ level: AccessLevel?) -> String {
        level?.umlSymbol ?? "~"
    }
}
