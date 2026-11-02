import SwiftSyntax
import AcaiCore

/// Extracts the language-level annotations shared by every Swift declaration — access level,
/// modifiers, attributes, generic parameters, and function signatures (parameters / return type).
/// Composes a `TypeReferenceExtractor` for the type-shaped pieces.
struct DeclarationSignatureExtractor {

    private let typeReferences = TypeReferenceExtractor()

    // MARK: - Access Level

    /// Access level of a Swift declaration; defaults to `internal` when no explicit modifier is
    /// present (language-specific — e.g. Kotlin defaults to `public` — hence living in `AcaiSwift`).
    func extractAccessLevel(from modifiers: DeclModifierListSyntax) -> AccessLevel {
        // Skip setter-scoped modifiers (`private(set)` etc.) — see `extractSetAccessLevel`.
        for modifier in modifiers where modifier.detail == nil {
            if let level = accessLevel(for: modifier.name.tokenKind) {
                return level
            }
        }
        return .internal
    }

    func extractSetAccessLevel(from modifiers: DeclModifierListSyntax) -> AccessLevel? {
        for modifier in modifiers where modifier.detail?.detail.text == "set" {
            if let level = accessLevel(for: modifier.name.tokenKind) {
                return level
            }
        }
        return nil
    }

    private func accessLevel(for tokenKind: TokenKind) -> AccessLevel? {
        switch tokenKind {
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
            return nil
        }
    }

    // MARK: - Modifiers

    private let keywordToModifier: [Keyword: Modifier] = [
        .static: .static, .class: .class, .final: .final,
        .override: .override, .mutating: .mutating,
        .nonmutating: .nonmutating, .lazy: .lazy,
        .weak: .weak, .unowned: .unowned,
        .optional: .optional, .required: .required,
        .convenience: .convenience, .nonisolated: .nonisolated,
        .consuming: .consuming, .borrowing: .borrowing
    ]

    func extractModifiers(from modifiers: DeclModifierListSyntax) -> [Modifier] {
        modifiers.compactMap { modifier in
            guard case .keyword(let keyword) = modifier.name.tokenKind else {
                return nil
            }
            return keywordToModifier[keyword]
        }
    }

    // MARK: - Generic Parameters

    func extractGenericParameters(
        from clause: GenericParameterClauseSyntax?,
        whereClause: GenericWhereClauseSyntax? = nil
    ) -> [GenericParameter] {
        var params: [GenericParameter] = (clause?.parameters.map { param in
            var constraints: [GenericConstraint] = []
            if let inheritedType = param.inheritedType {
                constraints.append(
                    GenericConstraint(
                        kind: .conformance,
                        type: typeReferences.extractTypeReference(from: inheritedType)
                    )
                )
            }
            return GenericParameter(name: param.name.text, constraints: constraints)
        }) ?? []

        guard let whereClause else { return params }
        // A constraint names the parameter it bounds in full: `T` bounds `T`, while `T.Element`
        // bounds an associated type and becomes a parameter of its own rather than bounding `T`.
        for (name, constraint) in extractWhereConstraints(whereClause) {
            if let idx = params.firstIndex(where: { $0.name == name }) {
                params[idx].constraints.append(constraint)
            } else {
                params.append(GenericParameter(name: name, constraints: [constraint]))
            }
        }
        return params
    }

    /// Only conformance requirements. A same-type requirement (`T == Int`, `T.Element == Int`) states an
    /// equality rather than a bound, so recording it would invent a parameter for the left-hand path.
    func extractWhereConstraints(
        _ whereClause: GenericWhereClauseSyntax
    ) -> [(name: String, constraint: GenericConstraint)] {
        whereClause.requirements.compactMap { requirement in
            guard case .conformanceRequirement(let conformance) = requirement.requirement else { return nil }
            return (
                conformance.leftType.trimmedDescription,
                GenericConstraint(
                    kind: .conformance,
                    type: typeReferences.extractTypeReference(from: conformance.rightType))
            )
        }
    }

    func extractAssociatedType(from node: AssociatedTypeDeclSyntax) -> GenericParameter {
        var constraints: [GenericConstraint] = []
        if let inheritance = node.inheritanceClause {
            for inherited in inheritance.inheritedTypes {
                constraints.append(
                    GenericConstraint(
                        kind: .conformance, type: typeReferences.extractTypeReference(from: inherited.type)))
            }
        }
        if let whereClause = node.genericWhereClause {
            constraints.append(contentsOf: extractWhereConstraints(whereClause).map(\.constraint))
        }
        return GenericParameter(name: node.name.text, constraints: constraints)
    }

    // MARK: - Attributes

    func extractAttributes(from attributes: AttributeListSyntax) -> [String] {
        attributes.compactMap { element in
            if let attr = element.as(AttributeSyntax.self) {
                return attr.trimmedDescription
            }
            return nil
        }
    }

    // MARK: - Function Signature

    func extractParameters(from parameterClause: FunctionParameterClauseSyntax) -> [Parameter] {
        parameterClause.parameters.map { param in
            extractParameter(from: param)
        }
    }

    func extractParameter(from param: FunctionParameterSyntax) -> Parameter {
        let externalName: String? = {
            if let firstName = param.firstName.tokenKind == .wildcard ? nil : param.firstName.text,
               firstName != param.secondName?.text {
                return firstName
            }
            return param.firstName.tokenKind == .wildcard ? nil : param.firstName.text
        }()

        let internalName = param.secondName?.text ?? param.firstName.text

        let typeRef: TypeReference? = typeReferences.extractTypeReference(from: param.type)

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

    func extractReturnType(from returnClause: ReturnClauseSyntax?) -> TypeReference? {
        guard let returnClause else { return nil }
        let ref = typeReferences.extractTypeReference(from: returnClause.type)
        if ref.name == "Void" { return nil }
        return ref
    }
}
