import UMLCore
import UMLTreeSitter

// MARK: - Members & Type Extraction

extension JSExtractor {

    // MARK: - Class Body

    func parseClassBody(_ bodyNode: Node, into typeDecl: inout TypeDeclaration) {
        let scope = CallSiteScope(
            knownProperties: buildPropertyMapFromBody(bodyNode),
            knownTypeNames: collectKnownTypeNames()
        )

        for child in bodyNode.children() {
            guard let childType = child.nodeType else { continue }
            if let member = extractClassBodyMember(child, childType: childType,
                                                   parentName: typeDecl.name,
                                                   scope: scope,
                                                   typeDecl: &typeDecl) {
                typeDecl.members.append(member)
            }
        }
    }

    private func extractClassBodyMember(
        _ child: Node,
        childType: String,
        parentName: String,
        scope: CallSiteScope,
        typeDecl: inout TypeDeclaration
    ) -> Member? {
        switch childType {
        case "method_definition", "abstract_method_definition":
            var member = extractMethodDefinition(child, parentName: parentName,
                                                 scope: scope)
            if childType == "abstract_method_definition", isTypeScript,
               !member.modifiers.contains(.abstract) {
                member.modifiers.append(.abstract)
            }
            if member.kind == .initializer, isTypeScript {
                extractConstructorParameterProperties(child, into: &typeDecl)
            }
            return member

        case "field_definition", "public_field_definition":
            return extractFieldDefinition(child)

        case "method_signature" where isTypeScript:
            return extractMethodSignature(child)

        case "abstract_method_signature" where isTypeScript:
            var member = extractMethodSignature(child)
            if !member.modifiers.contains(.abstract) {
                member.modifiers.append(.abstract)
            }
            return member

        case "property_signature" where isTypeScript:
            return extractPropertySignature(child)

        default:
            return nil
        }
    }

    /// Builds a `varName → typeName` map by pre-scanning the class body for field
    /// definitions and TypeScript constructor parameter properties.
    private func buildPropertyMapFromBody(_ bodyNode: Node) -> [String: String] {
        var map: [String: String] = [:]

        for child in bodyNode.children() {
            guard let childType = child.nodeType else { continue }

            if childType == "field_definition" || childType == "public_field_definition" {
                let member = extractFieldDefinition(child)
                if !member.modifiers.contains(.static), let typeName = member.type?.name {
                    map[member.name] = typeName
                }
            } else if childType == "method_definition", isTypeScript,
                      child.child(byFieldName: "name").map({ text($0) }) == "constructor",
                      let paramsNode = child.child(byFieldName: "parameters") {
                // TypeScript constructor parameter properties (public/private/protected/readonly)
                for param in paramsNode.children() {
                    guard let pType = param.nodeType,
                          pType == "required_parameter" || pType == "optional_parameter"
                    else { continue }
                    let accessMod = extractAccessibilityModifier(param)
                    let hasReadonly = param.hasDirectChildText("readonly", in: context)
                    guard accessMod != nil || hasReadonly else { continue }
                    let name = extractParameterName(param)
                    if !name.isEmpty, let typeRef = extractTypeAnnotation(param) {
                        map[name] = typeRef.name
                    }
                }
            }
        }
        return map
    }

    // MARK: - Method Definition

    private static let methodKeywordModifiers: [String: Modifier] = [
        "static": .static, "async": .async, "override": .override
    ]

    private func extractMethodDefinition(
        _ node: Node,
        parentName: String,
        scope: CallSiteScope = CallSiteScope()
    ) -> Member {
        let nodeLoc = loc(node)
        let nameNode = node.child(byFieldName: "name")
        let name = nameNode.map { text($0) } ?? ""
        let annotations = extractDecorators(node)

        let sig = extractMethodKindAndModifiers(
            node, name: name
        )

        let generics = isTypeScript ? extractTypeParameters(node) : []
        let params = node.child(byFieldName: "parameters").map { extractParameters($0) } ?? []
        let returnType = isTypeScript ? extractReturnTypeAnnotation(node) : nil

        let body = node.child(byFieldName: "body")
        let callSites = extractCallSites(from: body, scope: scope)

        return Member(
            name: name.isEmpty ? "_anonymous" : name,
            kind: sig.kind,
            accessLevel: sig.accessLevel,
            modifiers: sig.modifiers,
            type: returnType,
            parameters: params,
            genericParameters: generics,
            isComputed: sig.isComputed,
            annotations: annotations,
            location: nodeLoc,
            callSites: callSites,
            assignments: extractAssignments(from: body)
        )
    }

    /// Bundles the kind, access level, modifiers, and computed flag extracted from a method node.
    private struct MethodSignatureInfo {
        var kind: MemberKind
        var accessLevel: AccessLevel?
        var modifiers: [Modifier]
        var isComputed: Bool
    }

    private func extractMethodKindAndModifiers(
        _ node: Node,
        name: String
    ) -> MethodSignatureInfo {
        var kind: MemberKind = .method
        var modifiers: [Modifier] = []
        var isComputed = false

        for child in node.children() {
            let childText = text(child)
            if let modifier = Self.methodKeywordModifiers[childText] {
                modifiers.append(modifier)
            } else if childText == "get" || childText == "set" {
                isComputed = true
                kind = .property
            } else if childText == "abstract", isTypeScript {
                modifiers.append(.abstract)
            }
        }

        var accessLevel: AccessLevel?
        if isTypeScript { accessLevel = extractAccessibilityModifier(node) }
        if name.hasPrefix("#") { accessLevel = .private }
        if name == "constructor" { kind = .initializer }
        if isTypeScript, node.hasDirectChildText("readonly", in: context) {
            modifiers.append(.readonly)
        }

        return MethodSignatureInfo(kind: kind, accessLevel: accessLevel, modifiers: modifiers, isComputed: isComputed)
    }

    // MARK: - Field Definition

    private func extractFieldDefinition(_ node: Node) -> Member {
        let nodeLoc = loc(node)
        let nameNode = node.child(byFieldName: "property") ?? node.child(byFieldName: "name")
        let name = nameNode.map { text($0) } ?? ""

        var accessLevel: AccessLevel?
        var modifiers: [Modifier] = []
        let annotations = extractDecorators(node)

        if node.hasDirectChildText("static", in: context) {
            modifiers.append(.static)
        }

        if name.hasPrefix("#") {
            accessLevel = .private
        }

        if isTypeScript {
            if let acc = extractAccessibilityModifier(node) {
                accessLevel = acc
            }
            if node.hasDirectChildText("readonly", in: context) { modifiers.append(.readonly) }
            if node.hasDirectChildText("abstract", in: context) { modifiers.append(.abstract) }
            if node.hasDirectChildText("override", in: context) { modifiers.append(.override) }
            if node.hasDirectChildText("declare", in: context) { modifiers.append(.declare) }
        }

        var propType: TypeReference?
        if isTypeScript {
            propType = extractTypeAnnotation(node)
        }

        if node.hasDirectChildText("?", in: context) {
            propType?.isOptional = true
        }

        return Member(
            name: name.isEmpty ? "_unknown" : name,
            kind: .property,
            accessLevel: accessLevel,
            modifiers: modifiers,
            type: propType,
            annotations: annotations,
            location: nodeLoc,
            initialValue: node.child(byFieldName: "value").map { classifyValue($0) }
        )
    }

    // MARK: - Constructor Parameter Properties (TypeScript)

    private func extractConstructorParameterProperties(_ ctorNode: Node, into typeDecl: inout TypeDeclaration) {
        guard let paramsNode = ctorNode.child(byFieldName: "parameters") else { return }
        for child in paramsNode.children() {
            guard let childType = child.nodeType else { continue }
            guard childType == "required_parameter" || childType == "optional_parameter" else { continue }

            let accessMod = extractAccessibilityModifier(child)
            let hasReadonly = child.hasDirectChildText("readonly", in: context)
            guard accessMod != nil || hasReadonly else { continue }

            let paramName = extractParameterName(child)
            var modifiers: [Modifier] = []
            if hasReadonly { modifiers.append(.readonly) }

            let paramType = extractTypeAnnotation(child)
            typeDecl.members.append(Member(
                name: paramName,
                kind: .property,
                accessLevel: accessMod,
                modifiers: modifiers,
                type: paramType
            ))
        }
    }

    // MARK: - Interface Declaration

    mutating func extractInterfaceDeclaration(_ node: Node, isExported: Bool) -> TypeDeclaration {
        let nodeLoc = loc(node)
        let nameNode = node.child(byFieldName: "name")
        let name = nameNode.map { text($0) } ?? "_Anonymous"

        let generics = extractTypeParameters(node)
        var inherited: [TypeReference] = []

        for child in node.children() {
            guard let childType = child.nodeType else { continue }
            if childType == "extends_type_clause" || childType == "extends_clause" {
                for typeNode in child.namedChildren() {
                    let ref = extractTypeReferenceFromExpression(typeNode)
                    inherited.append(ref)
                    relationships.append(Relationship(kind: .conformance, source: name, target: ref.name))
                }
            }
        }

        var typeDecl = TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .interface,
            accessLevel: isExported ? .public : nil,
            genericParameters: generics,
            inheritedTypes: inherited,
            location: nodeLoc
        )

        if let body = node.child(byFieldName: "body") {
            parseInterfaceBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Interface Body

    private func parseInterfaceBody(_ bodyNode: Node, into typeDecl: inout TypeDeclaration) {
        for child in bodyNode.namedChildren() {
            guard let childType = child.nodeType else { continue }
            switch childType {
            case "property_signature":
                typeDecl.members.append(extractPropertySignature(child))
            case "method_signature":
                typeDecl.members.append(extractMethodSignature(child))
            case "call_signature":
                let params = extractParameters(child.child(byFieldName: "parameters") ?? child)
                let ret = extractReturnTypeAnnotation(child)
                typeDecl.members.append(Member(name: "call", kind: .method, type: ret, parameters: params))
            case "construct_signature":
                let params = extractParameters(child.child(byFieldName: "parameters") ?? child)
                let ret = extractReturnTypeAnnotation(child)
                typeDecl.members.append(Member(name: "new", kind: .initializer, type: ret, parameters: params))
            case "index_signature":
                break // Not modeled
            default:
                break
            }
        }
    }

    // MARK: - Property Signature

    private func extractPropertySignature(_ node: Node) -> Member {
        let nodeLoc = loc(node)
        let nameNode = node.child(byFieldName: "name")
        let name = nameNode.map { text($0) } ?? ""

        var accessLevel: AccessLevel?
        var modifiers: [Modifier] = []

        if let acc = extractAccessibilityModifier(node) {
            accessLevel = acc
        }
        if node.hasDirectChildText("readonly", in: context) {
            modifiers.append(.readonly)
        }

        var propType = extractTypeAnnotation(node)
        if node.hasDirectChildText("?", in: context) {
            propType?.isOptional = true
        }

        return Member(
            name: name, kind: .property,
            accessLevel: accessLevel,
            modifiers: modifiers,
            type: propType,
            location: nodeLoc
        )
    }

    // MARK: - Method Signature

    private func extractMethodSignature(_ node: Node) -> Member {
        let nodeLoc = loc(node)
        let nameNode = node.child(byFieldName: "name")
        let name = nameNode.map { text($0) } ?? ""

        let accessLevel = extractAccessibilityModifier(node)
        let generics = extractTypeParameters(node)
        let params: [Parameter]
        if let paramsNode = node.child(byFieldName: "parameters") {
            params = extractParameters(paramsNode)
        } else {
            params = []
        }
        let returnType = extractReturnTypeAnnotation(node)

        return Member(
            name: name, kind: .method,
            accessLevel: accessLevel,
            type: returnType,
            parameters: params,
            genericParameters: generics,
            location: nodeLoc
        )
    }

    // MARK: - Type Alias Declaration

    func extractTypeAliasDeclaration(_ node: Node, isExported: Bool) -> TypeDeclaration {
        let nodeLoc = loc(node)
        let nameNode = node.child(byFieldName: "name")
        let name = nameNode.map { text($0) } ?? ""
        let generics = extractTypeParameters(node)

        var targetText = ""
        if let valueNode = node.child(byFieldName: "value") {
            targetText = text(valueNode)
        }

        return TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .typeAlias,
            accessLevel: isExported ? .public : nil,
            genericParameters: generics,
            inheritedTypes: targetText.isEmpty ? [] : [TypeReference(name: targetText)],
            location: nodeLoc
        )
    }

    // MARK: - Enum Declaration

    func extractEnumDeclaration(_ node: Node, isExported: Bool) -> TypeDeclaration {
        let nodeLoc = loc(node)
        let nameNode = node.child(byFieldName: "name")
        let name = nameNode.map { text($0) } ?? ""

        var typeDecl = TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .enum,
            accessLevel: isExported ? .public : nil,
            location: nodeLoc
        )

        if let body = node.child(byFieldName: "body") {
            for child in body.namedChildren() {
                guard let childType = child.nodeType else { continue }
                if childType == "enum_assignment" {
                    let caseName: String
                    if let nameChild = child.child(byFieldName: "name") {
                        caseName = text(nameChild)
                    } else {
                        caseName = child.namedChildren().first.map { text($0) } ?? ""
                    }
                    var rawValue: String?
                    if let valueChild = child.child(byFieldName: "value") {
                        rawValue = text(valueChild)
                    }
                    typeDecl.enumCases.append(EnumCase(name: caseName, rawValue: rawValue))
                } else if childType == "property_identifier" || childType == "identifier" {
                    typeDecl.enumCases.append(EnumCase(name: text(child)))
                }
            }
        }
        return typeDecl
    }

    // MARK: - Module / Namespace

    mutating func extractModule(_ node: Node, isExported: Bool) -> [TypeDeclaration] {
        let name = node.child(byFieldName: "name").map { text($0) } ?? "_Module"
        var nestedTypes: [TypeDeclaration] = []
        var nestedFunctions: [Member] = []

        if let body = node.child(byFieldName: "body") {
            for child in body.children() {
                guard let childType = child.nodeType else { continue }
                if childType == "export_statement" {
                    let isDefault = child.hasDirectChildText("default", in: context)
                    let exportDecorators = extractDecorators(child)
                    for exportChild in child.children() {
                        let (newTypes, newFunctions) = dispatchDeclaration(
                        exportChild, isExported: true, isDefault: isDefault,
                        decorators: exportDecorators, namespace: name
                    )
                        nestedTypes += newTypes; nestedFunctions += newFunctions
                    }
                } else {
                    let (newTypes, newFunctions) = dispatchDeclaration(child, isExported: false, namespace: name)
                    nestedTypes += newTypes; nestedFunctions += newFunctions
                }
            }
        }

        freestandingFunctions.append(contentsOf: nestedFunctions)
        let nsDecl = TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .module,
            accessLevel: isExported ? .public : nil,
            nestedTypes: nestedTypes
        )
        return [nsDecl]
    }

    // MARK: - Function Declaration

    func extractFunctionDeclaration(_ node: Node, isExported: Bool) -> Member {
        let nodeLoc = loc(node)
        let name = node.child(byFieldName: "name").map { text($0) } ?? "_anonymous"
        var modifiers: [Modifier] = []
        if node.hasDirectChildText("async", in: context) { modifiers.append(.async) }
        let generics = isTypeScript ? extractTypeParameters(node) : []
        let params = node.child(byFieldName: "parameters").map { extractParameters($0) } ?? []
        let returnType = isTypeScript ? extractReturnTypeAnnotation(node) : nil
        return Member(
            name: name, kind: .method,
            accessLevel: isExported ? .public : nil,
            modifiers: modifiers, type: returnType,
            parameters: params, genericParameters: generics, location: nodeLoc
        )
    }
}
