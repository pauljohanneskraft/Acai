import UMLCore

enum UMLMemberFormatting {

    static func formatProperty(_ member: Member, collectionTypeNames: Set<String> = []) -> String {
        var result = accessSymbol(member.accessLevel)
        result += " "
        result += member.name
        if let type = member.type {
            result += ": " + typeRefString(type, collectionTypeNames: collectionTypeNames)
        }
        return result
    }

    static func formatMethod(_ member: Member, collectionTypeNames: Set<String> = []) -> String {
        var result = accessSymbol(member.accessLevel)
        result += " "
        result += member.name

        let paramStr = member.parameters.map { p in
            var parameterString = p.internalName
            if let parameterType = p.type {
                parameterString += ": " + typeRefString(parameterType, collectionTypeNames: collectionTypeNames)
            }
            return parameterString
        }.joined(separator: ", ")
        result += "(\(paramStr))"

        if let type = member.type {
            result += ": " + typeRefString(type, collectionTypeNames: collectionTypeNames)
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

    static func typeRefString(_ ref: TypeReference, collectionTypeNames: Set<String> = []) -> String {
        var typeString = ref.name
        if !ref.genericArguments.isEmpty {
            typeString += "<" + ref.genericArguments
                .map { typeRefString($0, collectionTypeNames: collectionTypeNames) }
                .joined(separator: ", ") + ">"
        }
        if ref.isOptional { typeString += "?" }
        // Append `[]` for an array unless the name is already a collection spelling in this
        // language (passed down from the diagram's `LanguageConfiguration`), so we don't render
        // `Array<T>[]`. The collection vocabulary is injected, never hardcoded here.
        if ref.isArray && !collectionTypeNames.contains(ref.name) { typeString += "[]" }
        return typeString
    }

    private static func accessSymbol(_ level: AccessLevel?) -> String {
        level?.umlSymbol ?? "~"
    }
}
