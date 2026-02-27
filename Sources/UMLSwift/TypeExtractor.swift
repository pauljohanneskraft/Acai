import SwiftSyntax
import SwiftParser
import UMLCore

enum TypeExtractor {

    // MARK: - Access Level

    static func extractAccessLevel(from modifiers: DeclModifierListSyntax) -> AccessLevel? {
        for modifier in modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.public): return .public
            case .keyword(.open): return .open
            case .keyword(.internal): return .internal
            case .keyword(.private): return .private
            case .keyword(.fileprivate): return .filePrivate
            case .keyword(.package): return .packagePrivate
            default: continue
            }
        }
        return nil
    }

    // MARK: - Modifiers

    static func extractModifiers(from modifiers: DeclModifierListSyntax) -> [Modifier] {
        var result: [Modifier] = []
        for modifier in modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.static): result.append(.static)
            case .keyword(.class): result.append(.class)
            case .keyword(.final): result.append(.final)
            case .keyword(.override): result.append(.override)
            case .keyword(.mutating): result.append(.mutating)
            case .keyword(.nonmutating): result.append(.nonmutating)
            case .keyword(.lazy): result.append(.lazy)
            case .keyword(.weak): result.append(.weak)
            case .keyword(.unowned): result.append(.unowned)
            case .keyword(.optional): result.append(.optional)
            case .keyword(.required): result.append(.required)
            case .keyword(.convenience): result.append(.convenience)
            case .keyword(.nonisolated): result.append(.nonisolated)
            case .keyword(.consuming): result.append(.consuming)
            case .keyword(.borrowing): result.append(.borrowing)
            default: continue
            }
        }
        return result
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
        return clause.inheritedTypes.map { inheritedType in
            extractTypeReference(from: inheritedType.type)
        }
    }

    // MARK: - Type Reference

    static func extractTypeReference(from typeSyntax: TypeSyntax) -> TypeReference {
        if let identifierType = typeSyntax.as(IdentifierTypeSyntax.self) {
            let genericArgs = identifierType.genericArgumentClause.map { clause in
                clause.arguments.map { extractTypeReference(from: $0.argument) }
            } ?? []
            return TypeReference(
                name: identifierType.name.text,
                genericArguments: genericArgs
            )
        }

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

        if let tupleType = typeSyntax.as(TupleTypeSyntax.self) {
            let elements = tupleType.elements.map { extractTypeReference(from: $0.type) }
            let name = "(" + elements.map(\.name).joined(separator: ", ") + ")"
            return TypeReference(name: name, genericArguments: elements)
        }

        if let functionType = typeSyntax.as(FunctionTypeSyntax.self) {
            let paramTypes = functionType.parameters.map { extractTypeReference(from: $0.type) }
            let returnType = extractTypeReference(from: functionType.returnClause.type)
            let paramString = paramTypes.map(\.name).joined(separator: ", ")
            let name = "(\(paramString)) -> \(returnType.name)"
            return TypeReference(name: name)
        }

        if let attributedType = typeSyntax.as(AttributedTypeSyntax.self) {
            return extractTypeReference(from: attributedType.baseType)
        }

        if let compositionType = typeSyntax.as(CompositionTypeSyntax.self) {
            let elements = compositionType.elements.map { extractTypeReference(from: $0.type) }
            let name = elements.map(\.name).joined(separator: " & ")
            return TypeReference(name: name)
        }

        if let someOrAnyType = typeSyntax.as(SomeOrAnyTypeSyntax.self) {
            let inner = extractTypeReference(from: someOrAnyType.constraint)
            let keyword = someOrAnyType.someOrAnySpecifier.text
            return TypeReference(name: "\(keyword) \(inner.name)")
        }

        if typeSyntax.as(MissingTypeSyntax.self) != nil {
            return TypeReference(name: "Void")
        }

        if let classRestriction = typeSyntax.as(ClassRestrictionTypeSyntax.self) {
            return TypeReference(name: classRestriction.classKeyword.text)
        }

        // Fallback: use the source text representation
        return TypeReference(name: typeSyntax.trimmedDescription)
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
            case .keyword(.consuming): modifiers.append(.consuming)
            case .keyword(.borrowing): modifiers.append(.borrowing)
            default: break
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

    // MARK: - Type Declaration Extraction

    static func extractClass(from node: ClassDeclSyntax, fileName: String, namespace: String?) -> TypeDeclaration {
        let name = node.name.text
        let qualifiedName = namespace.map { "\($0).\(name)" } ?? name
        return TypeDeclaration(
            id: qualifiedName,
            name: name,
            qualifiedName: qualifiedName,
            kind: .class,
            accessLevel: extractAccessLevel(from: node.modifiers),
            modifiers: extractModifiers(from: node.modifiers),
            genericParameters: extractGenericParameters(from: node.genericParameterClause),
            inheritedTypes: extractInheritedTypes(from: node.inheritanceClause),
            annotations: extractAttributes(from: node.attributes),
            namespace: namespace,
            location: sourceLocation(of: node, fileName: fileName)
        )
    }

    static func extractStruct(from node: StructDeclSyntax, fileName: String, namespace: String?) -> TypeDeclaration {
        let name = node.name.text
        let qualifiedName = namespace.map { "\($0).\(name)" } ?? name
        return TypeDeclaration(
            id: qualifiedName,
            name: name,
            qualifiedName: qualifiedName,
            kind: .struct,
            accessLevel: extractAccessLevel(from: node.modifiers),
            modifiers: extractModifiers(from: node.modifiers),
            genericParameters: extractGenericParameters(from: node.genericParameterClause),
            inheritedTypes: extractInheritedTypes(from: node.inheritanceClause),
            annotations: extractAttributes(from: node.attributes),
            namespace: namespace,
            location: sourceLocation(of: node, fileName: fileName)
        )
    }

    static func extractEnum(from node: EnumDeclSyntax, fileName: String, namespace: String?) -> TypeDeclaration {
        let name = node.name.text
        let qualifiedName = namespace.map { "\($0).\(name)" } ?? name
        return TypeDeclaration(
            id: qualifiedName,
            name: name,
            qualifiedName: qualifiedName,
            kind: .enum,
            accessLevel: extractAccessLevel(from: node.modifiers),
            modifiers: extractModifiers(from: node.modifiers),
            genericParameters: extractGenericParameters(from: node.genericParameterClause),
            inheritedTypes: extractInheritedTypes(from: node.inheritanceClause),
            annotations: extractAttributes(from: node.attributes),
            namespace: namespace,
            location: sourceLocation(of: node, fileName: fileName)
        )
    }

    static func extractProtocol(
        from node: ProtocolDeclSyntax, fileName: String, namespace: String?
    ) -> TypeDeclaration {
        let name = node.name.text
        let qualifiedName = namespace.map { "\($0).\(name)" } ?? name
        return TypeDeclaration(
            id: qualifiedName,
            name: name,
            qualifiedName: qualifiedName,
            kind: .protocol,
            accessLevel: extractAccessLevel(from: node.modifiers),
            modifiers: extractModifiers(from: node.modifiers),
            inheritedTypes: extractInheritedTypes(from: node.inheritanceClause),
            annotations: extractAttributes(from: node.attributes),
            namespace: namespace,
            location: sourceLocation(of: node, fileName: fileName)
        )
    }

    static func extractExtension(
        from node: ExtensionDeclSyntax, fileName: String, namespace: String?
    ) -> TypeDeclaration {
        let extendedName = node.extendedType.trimmedDescription
        let name = extendedName
        let qualifiedName = namespace.map { "\($0).\(name)" } ?? name
        return TypeDeclaration(
            id: "extension.\(qualifiedName)",
            name: name,
            qualifiedName: qualifiedName,
            kind: .extension,
            accessLevel: extractAccessLevel(from: node.modifiers),
            modifiers: extractModifiers(from: node.modifiers),
            inheritedTypes: extractInheritedTypes(from: node.inheritanceClause),
            annotations: extractAttributes(from: node.attributes),
            extensionOf: extendedName,
            namespace: namespace,
            location: sourceLocation(of: node, fileName: fileName)
        )
    }

    static func extractTypeAlias(
        from node: TypeAliasDeclSyntax, fileName: String, namespace: String?
    ) -> TypeDeclaration {
        let name = node.name.text
        let qualifiedName = namespace.map { "\($0).\(name)" } ?? name
        return TypeDeclaration(
            id: qualifiedName,
            name: name,
            qualifiedName: qualifiedName,
            kind: .typeAlias,
            accessLevel: extractAccessLevel(from: node.modifiers),
            modifiers: extractModifiers(from: node.modifiers),
            genericParameters: extractGenericParameters(from: node.genericParameterClause),
            inheritedTypes: [extractTypeReference(from: node.initializer.value)],
            annotations: extractAttributes(from: node.attributes),
            namespace: namespace,
            location: sourceLocation(of: node, fileName: fileName)
        )
    }

    static func extractActor(from node: ActorDeclSyntax, fileName: String, namespace: String?) -> TypeDeclaration {
        let name = node.name.text
        let qualifiedName = namespace.map { "\($0).\(name)" } ?? name
        return TypeDeclaration(
            id: qualifiedName,
            name: name,
            qualifiedName: qualifiedName,
            kind: .class,
            accessLevel: extractAccessLevel(from: node.modifiers),
            modifiers: extractModifiers(from: node.modifiers),
            genericParameters: extractGenericParameters(from: node.genericParameterClause),
            inheritedTypes: extractInheritedTypes(from: node.inheritanceClause),
            annotations: ["@actor"] + extractAttributes(from: node.attributes),
            namespace: namespace,
            location: sourceLocation(of: node, fileName: fileName)
        )
    }

    // MARK: - Source Location

    static func sourceLocation(of node: some SyntaxProtocol, fileName: String) -> UMLCore.SourceLocation {
        let position = node.positionAfterSkippingLeadingTrivia
        let sourceFile = node.root.as(SourceFileSyntax.self)!
        let converter = SourceLocationConverter(fileName: fileName, tree: sourceFile)
        let location = converter.location(for: position)
        return UMLCore.SourceLocation(
            filePath: fileName,
            line: location.line,
            column: location.column
        )
    }
}
