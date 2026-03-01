import SwiftSyntax
import SwiftParser
import UMLCore

enum TypeExtractor {

    // MARK: - Access Level

    static func extractAccessLevel(from modifiers: DeclModifierListSyntax) -> AccessLevel? {
        for modifier in modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.public):
                return .public
            case .keyword(.open):
                return .open
            case .keyword(.internal):
                return .internal
            case .keyword(.private):
                return .private
            case .keyword(.fileprivate):
                return .filePrivate
            case .keyword(.package):
                return .packagePrivate
            default:
                continue
            }
        }
        return nil
    }

    // MARK: - Modifiers

    private static let keywordToModifier: [Keyword: Modifier] = [
        .static: .static, .class: .class, .final: .final,
        .override: .override, .mutating: .mutating,
        .nonmutating: .nonmutating, .lazy: .lazy,
        .weak: .weak, .unowned: .unowned,
        .optional: .optional, .required: .required,
        .convenience: .convenience, .nonisolated: .nonisolated,
        .consuming: .consuming, .borrowing: .borrowing
    ]

    static func extractModifiers(from modifiers: DeclModifierListSyntax) -> [Modifier] {
        modifiers.compactMap { modifier in
            guard case .keyword(let keyword) = modifier.name.tokenKind else {
                return nil
            }
            return keywordToModifier[keyword]
        }
    }

    // MARK: - Generic Parameters

    static func extractGenericParameters(from clause: GenericParameterClauseSyntax?) -> [GenericParameter] {
        guard let clause else { return [] }
        return clause.parameters.map { param in
            var constraints: [GenericConstraint] = []
            if let inheritedType = param.inheritedType {
                constraints.append(
                    GenericConstraint(
                        kind: .conformance,
                        type: extractTypeReference(from: inheritedType)
                    )
                )
            }
            return GenericParameter(
                name: param.name.text,
                constraints: constraints
            )
        }
    }

    // MARK: - Inherited Types

    static func extractInheritedTypes(from clause: InheritanceClauseSyntax?) -> [TypeReference] {
        guard let clause else { return [] }
        return clause.inheritedTypes.flatMap { inheritedType -> [TypeReference] in
            flattenCompositionType(inheritedType.type)
        }
    }

    /// Expands a `CompositionTypeSyntax` (e.g. `A & B & C`) into individual
    /// type references. Non-composition types are returned as a single-element array.
    static func flattenCompositionType(_ typeSyntax: TypeSyntax) -> [TypeReference] {
        if let composition = typeSyntax.as(CompositionTypeSyntax.self) {
            return composition.elements.map { extractTypeReference(from: $0.type) }
        }
        return [extractTypeReference(from: typeSyntax)]
    }

    // MARK: - Type Reference

    static func extractTypeReference(from typeSyntax: TypeSyntax) -> TypeReference {
        if let result = extractWrapperType(from: typeSyntax) {
            return result
        }

        if let result = extractCollectionOrCompoundType(from: typeSyntax) {
            return result
        }

        if let identifierType = typeSyntax.as(IdentifierTypeSyntax.self) {
            let genericArgs = identifierType.genericArgumentClause.map { clause in
                clause.arguments.map { extractTypeReference(from: $0.argument) }
            } ?? []
            return TypeReference(
                name: identifierType.name.text,
                genericArguments: genericArgs
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

    // MARK: - Type Reference Helpers

    private static func extractWrapperType(from typeSyntax: TypeSyntax) -> TypeReference? {
        if let optionalType = typeSyntax.as(OptionalTypeSyntax.self) {
            var ref = extractTypeReference(from: optionalType.wrappedType)
            ref.isOptional = true
            ref.name += "?"
            return ref
        }

        if let implicitlyUnwrapped = typeSyntax.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            var ref = extractTypeReference(from: implicitlyUnwrapped.wrappedType)
            ref.isOptional = true
            ref.name += "!"
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

    private static func extractCollectionOrCompoundType(from typeSyntax: TypeSyntax) -> TypeReference? {
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
            return TypeReference(name: name)
        }

        return nil
    }

    // MARK: - Attributes

    static func extractAttributes(from attributes: AttributeListSyntax) -> [String] {
        attributes.compactMap { element in
            if let attr = element.as(AttributeSyntax.self) {
                return "@\(attr.attributeName.trimmedDescription)"
            }
            return nil
        }
    }

    // MARK: - Function Signature Extraction

    static func extractParameters(from parameterClause: FunctionParameterClauseSyntax) -> [Parameter] {
        parameterClause.parameters.map { param in
            extractParameter(from: param)
        }
    }

    static func extractParameter(from param: FunctionParameterSyntax) -> Parameter {
        let externalName: String? = {
            if let firstName = param.firstName.tokenKind == .wildcard ? nil : param.firstName.text,
               firstName != param.secondName?.text {
                return firstName
            }
            return param.firstName.tokenKind == .wildcard ? nil : param.firstName.text
        }()

        let internalName = param.secondName?.text ?? param.firstName.text

        let typeRef: TypeReference? = extractTypeReference(from: param.type)

        let defaultValue = param.defaultValue?.value.trimmedDescription

        let isVariadic = param.ellipsis != nil

        var modifiers: [Modifier] = []
        for specifier in param.modifiers {
            switch specifier.name.tokenKind {
            case .keyword(.consuming):
                modifiers.append(.consuming)
            case .keyword(.borrowing):
                modifiers.append(.borrowing)
            default:
                break
            }
        }

        return Parameter(
            externalName: externalName,
            internalName: internalName,
            type: typeRef,
            defaultValue: defaultValue,
            isVariadic: isVariadic,
            modifiers: modifiers
        )
    }

    static func extractReturnType(from returnClause: ReturnClauseSyntax?) -> TypeReference? {
        guard let returnClause else { return nil }
        let ref = extractTypeReference(from: returnClause.type)
        if ref.name == "Void" { return nil }
        return ref
    }

}
