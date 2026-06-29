// UML text formatting for diagram members, as methods on the values being formatted.
//
// Lives in UMLCore (rather than a rendering target) so every consumer — the DOT and Mermaid
// renderers in UMLDiagram and the SwiftUI canvas in UMLRender — shares one definition of how a
// type reference and a member line are spelled, instead of each re-implementing the recursive
// `Name<Args>?[]` rule and drifting apart.

extension Member {
    /// The UML access symbol for this member.
    public var umlAccessSymbol: String { accessLevel.umlSymbol }

    /// The UML "attribute" compartment line: `<sym> name: Type`.
    public func umlPropertyLine(collectionTypeNames: Set<String> = []) -> String {
        var result = "\(umlAccessSymbol) \(name)"
        if let type {
            result += ": " + type.umlDisplayString(collectionTypeNames: collectionTypeNames)
        }
        return result
    }

    /// The UML "operation" compartment line: `<sym> name(params): ReturnType`.
    public func umlMethodLine(collectionTypeNames: Set<String> = []) -> String {
        let params = parameters.map { parameter -> String in
            var rendered = parameter.internalName
            if let type = parameter.type {
                rendered += ": " + type.umlDisplayString(collectionTypeNames: collectionTypeNames)
            }
            return rendered
        }.joined(separator: ", ")
        var result = "\(umlAccessSymbol) \(name)(\(params))"
        if let type {
            result += ": " + type.umlDisplayString(collectionTypeNames: collectionTypeNames)
        }
        return result
    }
}

extension EnumCase {
    /// The UML enum-case line: `name`, or `name = rawValue` when a raw value is present.
    public var umlCaseLine: String {
        if let rawValue {
            return "\(name) = \(rawValue)"
        }
        return name
    }
}

extension TypeReference {
    /// The display string: `Name<Args>?[]` — generic arguments, optionality, and an array suffix
    /// unless the name is already a collection spelling in `collectionTypeNames` (so `Array<T>` /
    /// `List<T>` don't render with a trailing `[]`). The collection vocabulary is injected, never
    /// hardcoded here.
    public func umlDisplayString(collectionTypeNames: Set<String> = []) -> String {
        var typeString = name
        if !genericArguments.isEmpty {
            typeString += "<" + genericArguments
                .map { $0.umlDisplayString(collectionTypeNames: collectionTypeNames) }
                .joined(separator: ", ") + ">"
        }
        if isOptional { typeString += "?" }
        if isArray && !collectionTypeNames.contains(name) { typeString += "[]" }
        return typeString
    }
}
