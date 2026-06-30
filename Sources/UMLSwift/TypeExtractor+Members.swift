import SwiftSyntax
import UMLCore

extension TypeExtractor {

    // MARK: - Declaration Extraction

    func extractFunction(
        from node: FunctionDeclSyntax,
        fileName: String,
        callSites: [CallSite] = [],
        assignments: [VariableAssignment] = []
    ) -> Member {
        let modifiers = extractModifiers(from: node.modifiers)
        let accessLevel = extractAccessLevel(from: node.modifiers)
        let annotations = extractAttributes(from: node.attributes)
        let genericParams = extractGenericParameters(
            from: node.genericParameterClause, whereClause: node.genericWhereClause)
        let parameters = extractParameters(from: node.signature.parameterClause)
        let returnType = extractReturnType(from: node.signature.returnClause)

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
            location: sourceLocation(of: node, fileName: fileName),
            callSites: callSites,
            assignments: assignments
        )
    }

    func extractVariable(from node: VariableDeclSyntax, fileName: String) -> [Member] {
        let accessLevel = extractAccessLevel(from: node.modifiers)
        let setAccess = extractSetAccessLevel(from: node.modifiers)
        let modifiers = extractModifiers(from: node.modifiers)
        let annotations = extractAttributes(from: node.attributes)
        let location = sourceLocation(of: node, fileName: fileName)
        let bindings = Array(node.bindings)

        func makeMember(
            name: String,
            type: TypeReference?,
            isComputed: Bool,
            initialValue: VariableAssignment.Value? = nil
        ) -> Member {
            Member(
                name: name,
                kind: .property,
                accessLevel: accessLevel,
                setAccessLevel: setAccess,
                modifiers: modifiers,
                type: type,
                isComputed: isComputed,
                annotations: annotations,
                location: location,
                initialValue: initialValue
            )
        }

        var members: [Member] = []
        for (index, binding) in bindings.enumerated() {
            // A binding may omit its type annotation and inherit it from a later
            // binding in the same declaration, e.g. `let a, b: Int`.
            let annotationType: TypeSyntax? = binding.typeAnnotation?.type
                ?? bindings[index...].lazy.compactMap { $0.typeAnnotation?.type }.first

            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                members.append(makeMember(
                    name: pattern.identifier.text,
                    type: annotationType.map { extractTypeReference(from: $0) },
                    isComputed: isComputedBinding(binding),
                    initialValue: binding.initializer.map { SwiftValueClassifier().classify($0.value) }
                ))
            } else if let tuple = binding.pattern.as(TuplePatternSyntax.self) {
                // Decompose `let (a, b) = …` into one member per element.
                let tupleType = annotationType?.as(TupleTypeSyntax.self)
                let elementTypes = tupleType.map { Array($0.elements) }
                for (elementIndex, element) in tuple.elements.enumerated() {
                    guard let elementId = element.pattern.as(IdentifierPatternSyntax.self) else { continue }
                    let elementType = elementTypes.flatMap {
                        elementIndex < $0.count ? extractTypeReference(from: $0[elementIndex].type) : nil
                    }
                    members.append(makeMember(
                        name: elementId.identifier.text, type: elementType, isComputed: false))
                }
            }
        }
        return members
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
        assignments: [VariableAssignment] = []
    ) -> Member {
        let accessLevel = extractAccessLevel(from: node.modifiers)
        var modifiers = extractModifiers(from: node.modifiers)
        let annotations = extractAttributes(from: node.attributes)
        let genericParams = extractGenericParameters(
            from: node.genericParameterClause, whereClause: node.genericWhereClause)
        let parameters = extractParameters(from: node.signature.parameterClause)

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
            location: sourceLocation(of: node, fileName: fileName),
            callSites: callSites,
            assignments: assignments
        )
    }

    func extractDeinitializer(from node: DeinitializerDeclSyntax, fileName: String) -> Member {
        let accessLevel = extractAccessLevel(from: node.modifiers)
        let modifiers = extractModifiers(from: node.modifiers)

        return Member(
            name: "deinit",
            kind: .deinitializer,
            accessLevel: accessLevel,
            modifiers: modifiers,
            location: sourceLocation(of: node, fileName: fileName)
        )
    }

    func extractSubscript(from node: SubscriptDeclSyntax, fileName: String) -> Member {
        let accessLevel = extractAccessLevel(from: node.modifiers)
        let modifiers = extractModifiers(from: node.modifiers)
        let annotations = extractAttributes(from: node.attributes)
        let genericParams = extractGenericParameters(
            from: node.genericParameterClause, whereClause: node.genericWhereClause)

        let parameters = node.parameterClause.parameters.map { param in
            extractParameter(from: param)
        }

        let returnType = extractTypeReference(from: node.returnClause.type)

        return Member(
            name: "subscript",
            kind: .subscript,
            accessLevel: accessLevel,
            modifiers: modifiers,
            type: returnType,
            parameters: parameters,
            genericParameters: genericParams,
            annotations: annotations,
            location: sourceLocation(of: node, fileName: fileName)
        )
    }

    func extractEnumCases(from node: EnumCaseDeclSyntax, fileName: String) -> [EnumCase] {
        node.elements.map { element in
            let associatedValues: [Parameter] = element.parameterClause.map { clause in
                clause.parameters.map { param in
                    let externalName = param.firstName?.text
                    let internalName = param.secondName?.text ?? param.firstName?.text ?? "_"
                    let typeRef = extractTypeReference(from: param.type)
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
                location: sourceLocation(of: node, fileName: fileName)
            )
        }
    }
}
