import SwiftSyntax
import UMLCore

/// Extracts a type's members (functions, properties, initializers, deinitializers, subscripts, and
/// enum cases) from their SwiftSyntax declarations. Composes the shared signature/type-reference/
/// location helpers rather than re-deriving them.
struct MemberExtractor {

    private let signatures = DeclarationSignatureExtractor()
    private let typeReferences = TypeReferenceExtractor()
    private let sourceLocations = SourceLocationResolver()
    /// Simple names of every type declared in the file — the same recognition set
    /// `CallSiteCollector.knownTypeNames` uses, kept identical so a property's inferred type
    /// (below) and a call's resolved receiver type agree on what counts as a construction.
    private let knownTypeNames: Set<String>

    init(knownTypeNames: Set<String> = []) {
        self.knownTypeNames = knownTypeNames
    }

    func extractFunction(
        from node: FunctionDeclSyntax,
        fileName: String,
        callSites: [CallSite] = [],
        assignments: [VariableAssignment] = [],
        fieldReads: [FieldAccess] = []
    ) -> Member {
        let modifiers = signatures.extractModifiers(from: node.modifiers)
        let accessLevel = signatures.extractAccessLevel(from: node.modifiers)
        let annotations = signatures.extractAttributes(from: node.attributes)
        let genericParams = signatures.extractGenericParameters(
            from: node.genericParameterClause, whereClause: node.genericWhereClause)
        let parameters = signatures.extractParameters(from: node.signature.parameterClause)
        let returnType = signatures.extractReturnType(from: node.signature.returnClause)

        var effectModifiers: [Modifier] = modifiers
        if node.signature.effectSpecifiers?.asyncSpecifier != nil {
            effectModifiers.append(.async)
        }
        if node.signature.effectSpecifiers?.throwsClause != nil {
            effectModifiers.append(.throws)
        }

        return Member(
            name: node.name.text,
            kind: .method,
            accessLevel: accessLevel,
            modifiers: effectModifiers,
            type: returnType,
            parameters: parameters,
            genericParameters: genericParams,
            annotations: annotations,
            location: sourceLocations.sourceLocation(of: node, fileName: fileName),
            callSites: callSites,
            assignments: assignments,
            fieldReads: fieldReads,
            cyclomaticComplexity: SwiftCyclomaticComplexity(body: node.body).value
        )
    }

    func extractVariable(from node: VariableDeclSyntax, fileName: String) -> [Member] {
        let attributes = PropertyAttributes(
            accessLevel: signatures.extractAccessLevel(from: node.modifiers),
            setAccessLevel: signatures.extractSetAccessLevel(from: node.modifiers),
            modifiers: signatures.extractModifiers(from: node.modifiers),
            annotations: signatures.extractAttributes(from: node.attributes),
            location: sourceLocations.sourceLocation(of: node, fileName: fileName)
        )
        let bindings = Array(node.bindings)

        var members: [Member] = []
        for (index, binding) in bindings.enumerated() {
            // A binding may omit its type annotation and inherit it from a later
            // binding in the same declaration, e.g. `let a, b: Int`.
            let annotationType: TypeSyntax? = binding.typeAnnotation?.type
                ?? bindings[index...].lazy.compactMap { $0.typeAnnotation?.type }.first

            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                let resolvedType = annotationType.map { typeReferences.extractTypeReference(from: $0) }
                    ?? constructedType(from: binding.initializer?.value)
                members.append(makeProperty(
                    name: pattern.identifier.text,
                    type: resolvedType,
                    isComputed: isComputedBinding(binding),
                    initialValue: binding.initializer.map { SwiftValueClassifier().classify($0.value) },
                    attributes: attributes
                ))
            } else if let tuple = binding.pattern.as(TuplePatternSyntax.self) {
                members.append(contentsOf: tupleMembers(
                    of: tuple, annotationType: annotationType, attributes: attributes))
            }
        }
        return members
    }

    /// The binding-independent attributes shared by every property member of one `var`/`let` decl.
    private struct PropertyAttributes {
        let accessLevel: AccessLevel
        let setAccessLevel: AccessLevel?
        let modifiers: [Modifier]
        let annotations: [String]
        let location: UMLCore.SourceLocation
    }

    private func makeProperty(
        name: String,
        type: TypeReference?,
        isComputed: Bool,
        initialValue: VariableAssignment.Value? = nil,
        attributes: PropertyAttributes
    ) -> Member {
        Member(
            name: name,
            kind: .property,
            accessLevel: attributes.accessLevel,
            setAccessLevel: attributes.setAccessLevel,
            modifiers: attributes.modifiers,
            type: type,
            isComputed: isComputed,
            annotations: attributes.annotations,
            location: attributes.location,
            initialValue: initialValue
        )
    }

    /// Decomposes `let (a, b) = …` into one member per element, pairing each with its tuple-type slot.
    private func tupleMembers(
        of tuple: TuplePatternSyntax,
        annotationType: TypeSyntax?,
        attributes: PropertyAttributes
    ) -> [Member] {
        let elementTypes = annotationType?.as(TupleTypeSyntax.self).map { Array($0.elements) }
        return tuple.elements.enumerated().compactMap { elementIndex, element in
            guard let elementId = element.pattern.as(IdentifierPatternSyntax.self) else { return nil }
            let elementType = elementTypes.flatMap {
                elementIndex < $0.count
                    ? typeReferences.extractTypeReference(from: $0[elementIndex].type) : nil
            }
            return makeProperty(
                name: elementId.identifier.text, type: elementType, isComputed: false,
                attributes: attributes)
        }
    }

    /// Infers a stored property's type from a direct construction initializer (`= TypeName()`) when
    /// there's no explicit annotation — the sibling of `CallSiteCollector.constructedTypeName` for
    /// locals, extended to stored properties. Without this, a composed collaborator declared the
    /// idiomatic way (`private let helper = Helper()`) gets no recorded type, so `buildPropertyMap()`
    /// never learns it and calls through it (`helper.doThing()`) can't resolve.
    private func constructedType(from value: ExprSyntax?) -> TypeReference? {
        guard let call = value?.as(FunctionCallExprSyntax.self),
              let declRef = unwrappedCallee(call.calledExpression).as(DeclReferenceExprSyntax.self)
        else { return nil }
        let name = declRef.baseName.text
        guard knownTypeNames.contains(name) || name.first?.isUppercase == true else { return nil }
        return TypeReference(name: name)
    }

    /// Strips `Foo<T>()` generic-specialisation and `Foo?()` optional-chaining wrappers so the callee
    /// reduces to its underlying `DeclReferenceExprSyntax`. Mirrors `CallSiteCollector.unwrappedCallee`.
    private func unwrappedCallee(_ expr: ExprSyntax) -> ExprSyntax {
        if let generic = expr.as(GenericSpecializationExprSyntax.self) { return generic.expression }
        if let optional = expr.as(OptionalChainingExprSyntax.self) { return optional.expression }
        return expr
    }

    /// Whether a binding declares a computed property (has an explicit getter),
    /// as opposed to a stored property (no accessor, or only `didSet`/`willSet`).
    private func isComputedBinding(_ binding: PatternBindingSyntax) -> Bool {
        guard let accessor = binding.accessorBlock else { return false }
        switch accessor.accessors {
        case .getter:
            return true
        case .accessors(let accessors):
            return accessors.contains { $0.accessorSpecifier.tokenKind == .keyword(.get) }
        }
    }

    func extractInitializer(
        from node: InitializerDeclSyntax,
        fileName: String,
        callSites: [CallSite] = [],
        assignments: [VariableAssignment] = [],
        fieldReads: [FieldAccess] = []
    ) -> Member {
        let accessLevel = signatures.extractAccessLevel(from: node.modifiers)
        var modifiers = signatures.extractModifiers(from: node.modifiers)
        let annotations = signatures.extractAttributes(from: node.attributes)
        let genericParams = signatures.extractGenericParameters(
            from: node.genericParameterClause, whereClause: node.genericWhereClause)
        let parameters = signatures.extractParameters(from: node.signature.parameterClause)

        if node.signature.effectSpecifiers?.asyncSpecifier != nil {
            modifiers.append(.async)
        }
        if node.signature.effectSpecifiers?.throwsClause != nil {
            modifiers.append(.throws)
        }

        return Member(
            name: "init",
            kind: .initializer,
            accessLevel: accessLevel,
            modifiers: modifiers,
            parameters: parameters,
            genericParameters: genericParams,
            annotations: annotations,
            location: sourceLocations.sourceLocation(of: node, fileName: fileName),
            callSites: callSites,
            assignments: assignments,
            fieldReads: fieldReads,
            cyclomaticComplexity: SwiftCyclomaticComplexity(body: node.body).value
        )
    }

    func extractDeinitializer(from node: DeinitializerDeclSyntax, fileName: String) -> Member {
        let accessLevel = signatures.extractAccessLevel(from: node.modifiers)
        let modifiers = signatures.extractModifiers(from: node.modifiers)

        return Member(
            name: "deinit",
            kind: .deinitializer,
            accessLevel: accessLevel,
            modifiers: modifiers,
            location: sourceLocations.sourceLocation(of: node, fileName: fileName)
        )
    }

    func extractSubscript(from node: SubscriptDeclSyntax, fileName: String) -> Member {
        let accessLevel = signatures.extractAccessLevel(from: node.modifiers)
        let modifiers = signatures.extractModifiers(from: node.modifiers)
        let annotations = signatures.extractAttributes(from: node.attributes)
        let genericParams = signatures.extractGenericParameters(
            from: node.genericParameterClause, whereClause: node.genericWhereClause)

        let parameters = node.parameterClause.parameters.map { param in
            signatures.extractParameter(from: param)
        }

        let returnType = typeReferences.extractTypeReference(from: node.returnClause.type)

        return Member(
            name: "subscript",
            kind: .subscript,
            accessLevel: accessLevel,
            modifiers: modifiers,
            type: returnType,
            parameters: parameters,
            genericParameters: genericParams,
            annotations: annotations,
            location: sourceLocations.sourceLocation(of: node, fileName: fileName)
        )
    }

    func extractEnumCases(from node: EnumCaseDeclSyntax, fileName: String) -> [EnumCase] {
        node.elements.map { element in
            let associatedValues: [Parameter] = element.parameterClause.map { clause in
                clause.parameters.map { param in
                    let externalName = param.firstName?.text
                    let internalName = param.secondName?.text ?? param.firstName?.text ?? "_"
                    let typeRef = typeReferences.extractTypeReference(from: param.type)
                    let defaultValue = param.defaultValue?.value.trimmedDescription
                    return Parameter(
                        externalName: externalName,
                        internalName: internalName,
                        type: typeRef,
                        defaultValue: defaultValue
                    )
                }
            } ?? []

            let rawValue = element.rawValue?.value.trimmedDescription

            return EnumCase(
                name: element.name.text,
                rawValue: rawValue,
                associatedValues: associatedValues,
                location: sourceLocations.sourceLocation(of: node, fileName: fileName)
            )
        }
    }
}
