import SwiftSyntax
import UMLCore

extension TypeExtractor {

    // MARK: - Declaration Extraction

    static func extractFunction(
        from node: FunctionDeclSyntax,
        fileName: String,
        callSites: [CallSite] = []
    ) -> Member {
        let modifiers = extractModifiers(from: node.modifiers)
        let accessLevel = extractAccessLevel(from: node.modifiers)
        let annotations = extractAttributes(from: node.attributes)
        let genericParams = extractGenericParameters(from: node.genericParameterClause)
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
            callSites: callSites
        )
    }

    static func extractVariable(from node: VariableDeclSyntax, fileName: String) -> [Member] {
        let accessLevel = extractAccessLevel(from: node.modifiers)
        let modifiers = extractModifiers(from: node.modifiers)
        let annotations = extractAttributes(from: node.attributes)

        return node.bindings.compactMap { binding -> Member? in
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                return nil
            }

            let name = pattern.identifier.text
            let typeRef = binding.typeAnnotation.map { extractTypeReference(from: $0.type) }

            let isComputed: Bool = {
                guard let accessor = binding.accessorBlock else { return false }
                switch accessor.accessors {
                case .getter:
                    return true
                case .accessors(let accessors):
                    return accessors.contains { accessor in
                        accessor.accessorSpecifier.tokenKind == .keyword(.get)
                    }
                }
            }()

            return Member(
                name: name,
                kind: .property,
                accessLevel: accessLevel,
                modifiers: modifiers,
                type: typeRef,
                isComputed: isComputed,
                annotations: annotations,
                location: sourceLocation(of: node, fileName: fileName)
            )
        }
    }

    static func extractInitializer(
        from node: InitializerDeclSyntax,
        fileName: String,
        callSites: [CallSite] = []
    ) -> Member {
        let accessLevel = extractAccessLevel(from: node.modifiers)
        var modifiers = extractModifiers(from: node.modifiers)
        let annotations = extractAttributes(from: node.attributes)
        let genericParams = extractGenericParameters(from: node.genericParameterClause)
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
            callSites: callSites
        )
    }

    static func extractDeinitializer(from node: DeinitializerDeclSyntax, fileName: String) -> Member {
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

    static func extractSubscript(from node: SubscriptDeclSyntax, fileName: String) -> Member {
        let accessLevel = extractAccessLevel(from: node.modifiers)
        let modifiers = extractModifiers(from: node.modifiers)
        let annotations = extractAttributes(from: node.attributes)
        let genericParams = extractGenericParameters(from: node.genericParameterClause)

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

    static func extractEnumCases(from node: EnumCaseDeclSyntax, fileName: String) -> [EnumCase] {
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
