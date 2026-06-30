import SwiftSyntax
import UMLCore

/// Turns a SwiftSyntax `TypeSyntax` into a UMLCore `TypeReference`, normalising sugar spellings
/// (`T?`/`[T]`/`[K: V]`) and unwrapping wrappers (`some`/`any`, attributed, implicitly-unwrapped).
/// Owns all the per-syntax-node type-shape knowledge so the higher-level extractors don't have to.
struct TypeReferenceExtractor {

    func extractTypeReference(from typeSyntax: TypeSyntax) -> TypeReference {
        if let result = extractWrapperType(from: typeSyntax) {
            return result
        }

        if let result = extractCollectionOrCompoundType(from: typeSyntax) {
            return result
        }

        if let identifierType = typeSyntax.as(IdentifierTypeSyntax.self) {
            let name = identifierType.name.text
            let genericArgs = identifierType.genericArgumentClause.map { clause in
                clause.arguments.map { extractTypeReference(from: $0.argument) }
            } ?? []
            // Normalize sugar-equivalent spellings so `Optional<T>`/`Array<T>` match
            // `T?`/`[T]`.
            if name == "Optional", let inner = genericArgs.first {
                var ref = inner
                ref.isOptional = true
                return ref
            }
            return TypeReference(
                name: name,
                genericArguments: genericArgs,
                isArray: name == "Array" && !genericArgs.isEmpty
            )
        }

        if let memberType = typeSyntax.as(MemberTypeSyntax.self) {
            let baseName = extractTypeReference(from: memberType.baseType).name
            let memberName = memberType.name.text
            let genericArgs = memberType.genericArgumentClause.map { clause in
                clause.arguments.map { extractTypeReference(from: $0.argument) }
            } ?? []
            return TypeReference(
                name: "\(baseName).\(memberName)",
                genericArguments: genericArgs
            )
        }

        if let functionType = typeSyntax.as(FunctionTypeSyntax.self) {
            let paramTypes = functionType.parameters.map { extractTypeReference(from: $0.type) }
            let returnType = extractTypeReference(from: functionType.returnClause.type)
            let paramString = paramTypes.map(\.name).joined(separator: ", ")
            let name = "(\(paramString)) -> \(returnType.name)"
            return TypeReference(name: name)
        }

        if typeSyntax.as(MissingTypeSyntax.self) != nil {
            return TypeReference(name: "Void")
        }

        // Fallback: use the source text representation
        return TypeReference(name: typeSyntax.trimmedDescription)
    }

    /// Expands a `CompositionTypeSyntax` (e.g. `A & B & C`) into individual
    /// type references. Non-composition types are returned as a single-element array.
    func flattenCompositionType(_ typeSyntax: TypeSyntax) -> [TypeReference] {
        if let composition = typeSyntax.as(CompositionTypeSyntax.self) {
            return composition.elements.map { extractTypeReference(from: $0.type) }
        }
        return [extractTypeReference(from: typeSyntax)]
    }

    func extractInheritedTypes(from clause: InheritanceClauseSyntax?) -> [TypeReference] {
        guard let clause else { return [] }
        return clause.inheritedTypes.flatMap { inheritedType -> [TypeReference] in
            flattenCompositionType(inheritedType.type)
        }
    }

    // MARK: - Helpers

    private func extractWrapperType(from typeSyntax: TypeSyntax) -> TypeReference? {
        if let optionalType = typeSyntax.as(OptionalTypeSyntax.self) {
            var ref = extractTypeReference(from: optionalType.wrappedType)
            ref.isOptional = true
            return ref
        }

        if let implicitlyUnwrapped = typeSyntax.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            var ref = extractTypeReference(from: implicitlyUnwrapped.wrappedType)
            ref.isOptional = true
            return ref
        }

        if let attributedType = typeSyntax.as(AttributedTypeSyntax.self) {
            return extractTypeReference(from: attributedType.baseType)
        }

        if let someOrAnyType = typeSyntax.as(SomeOrAnyTypeSyntax.self) {
            let inner = extractTypeReference(from: someOrAnyType.constraint)
            let keyword = someOrAnyType.someOrAnySpecifier.text
            return TypeReference(name: "\(keyword) \(inner.name)")
        }

        if let classRestriction = typeSyntax.as(ClassRestrictionTypeSyntax.self) {
            return TypeReference(name: classRestriction.classKeyword.text)
        }

        return nil
    }

    private func extractCollectionOrCompoundType(from typeSyntax: TypeSyntax) -> TypeReference? {
        if let arrayType = typeSyntax.as(ArrayTypeSyntax.self) {
            let elementRef = extractTypeReference(from: arrayType.element)
            return TypeReference(
                name: "Array",
                genericArguments: [elementRef],
                isArray: true
            )
        }

        if let dictType = typeSyntax.as(DictionaryTypeSyntax.self) {
            let keyRef = extractTypeReference(from: dictType.key)
            let valueRef = extractTypeReference(from: dictType.value)
            return TypeReference(
                name: "Dictionary",
                genericArguments: [keyRef, valueRef]
            )
        }

        if let tupleType = typeSyntax.as(TupleTypeSyntax.self) {
            let elements = tupleType.elements.map { extractTypeReference(from: $0.type) }
            let name = "(" + elements.map(\.name).joined(separator: ", ") + ")"
            return TypeReference(name: name, genericArguments: elements)
        }

        if let compositionType = typeSyntax.as(CompositionTypeSyntax.self) {
            let elements = compositionType.elements.map { extractTypeReference(from: $0.type) }
            let name = elements.map(\.name).joined(separator: " & ")
            return TypeReference(name: name, genericArguments: elements)
        }

        return nil
    }
}
