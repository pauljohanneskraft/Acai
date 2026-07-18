import AcaiCore
import AcaiTreeSitter

// MARK: - Members & Type Extraction

extension JSExtractor {

    // MARK: - Class Body

    func parseClassBody(_ bodyNode: Node, into typeDecl: inout TypeDeclaration) {
        let scope = CallSiteScope(
            knownProperties: buildPropertyMapFromBody(bodyNode),
            knownTypeNames: declaredTypeNames,
            knownMethodReturnTypes: buildMethodReturnTypeMapFromBody(bodyNode)
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
            return extractFieldDefinition(child, scope: scope)

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

    /// A `methodName → returnTypeName` map from the class body's *direct* `method_definition`
    /// children (TypeScript only — JS has no return-type annotations), so a same-type method call
    /// with an unambiguous return type — including one declared later in the type — can seed a
    /// local's type (RC-I). Overloaded names with differing return types are dropped rather than
    /// guessed.
    private func buildMethodReturnTypeMapFromBody(_ bodyNode: Node) -> [String: String] {
        guard isTypeScript else { return [:] }
        var typesByName: [String: Set<String>] = [:]
        for child in bodyNode.children() where child.nodeType == "method_definition" {
            guard let nameNode = child.child(byFieldName: "name"),
                  let returnType = extractReturnTypeAnnotation(child)
            else { continue }
            typesByName[text(nameNode), default: []].insert(returnType.name)
        }
        return typesByName.compactMapValues { $0.count == 1 ? $0.first : nil }
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
        let callSites = extractCallSites(from: body, scope: scope.merging(parameters: params))

        return Member(
            name: name.isEmpty ? "_anonymous" : name,
            kind: sig.kind,
            accessLevel: sig.accessLevel ?? .internal,
            modifiers: sig.modifiers,
            type: returnType,
            parameters: params,
            genericParameters: generics,
            isComputed: sig.isComputed,
            annotations: annotations,
            location: nodeLoc,
            callSites: callSites,
            assignments: extractAssignments(from: body),
            fieldReads: fieldReadResolver.reads(in: body, scope: scope),
            referencedTypeNames: referencedTypeNames(in: body),
            cyclomaticComplexity: cyclomaticComplexity(in: body, branchKinds: Self.branchNodeKinds)
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

    private func extractFieldDefinition(_ node: Node, scope: CallSiteScope = CallSiteScope()) -> Member {
        let nodeLoc = loc(node)
        let nameNode = node.child(byFieldName: "property") ?? node.child(byFieldName: "name")
        let name = nameNode.map { text($0) } ?? ""

        var accessLevel: AccessLevel? = name.hasPrefix("#") ? .private : nil
        if isTypeScript, let acc = extractAccessibilityModifier(node) {
            accessLevel = acc
        }

        var propType = isTypeScript ? extractTypeAnnotation(node) : nil
        // No (or no TypeScript) annotation — fall back to inferring the type from a direct
        // construction initializer (`private cache = new ImageCache();`), the same heuristic
        // `localBindings` already applies to locals. Without this, a composed collaborator field
        // gets no recorded type, so calls through it (`this.cache.process()`) can't resolve.
        if propType == nil {
            propType = constructedType(fromFieldValue: node.child(byFieldName: "value"))
        }
        if node.hasDirectChildText("?", in: context) {
            propType?.isOptional = true
        }

        return Member(
            name: name.isEmpty ? "_unknown" : name,
            kind: .property,
            accessLevel: accessLevel ?? .internal,
            modifiers: fieldModifiers(node),
            type: propType,
            annotations: extractDecorators(node),
            location: nodeLoc,
            callSites: extractCallSites(from: node.child(byFieldName: "value"), scope: scope),
            initialValue: node.child(byFieldName: "value").map { classifyValue($0) },
            referencedTypeNames: referencedTypeNames(in: node.child(byFieldName: "value"))
        )
    }

    private func fieldModifiers(_ node: Node) -> [Modifier] {
        var modifiers: [Modifier] = []
        if node.hasDirectChildText("static", in: context) { modifiers.append(.static) }
        guard isTypeScript else { return modifiers }
        if node.hasDirectChildText("readonly", in: context) { modifiers.append(.readonly) }
        if node.hasDirectChildText("abstract", in: context) { modifiers.append(.abstract) }
        if node.hasDirectChildText("override", in: context) { modifiers.append(.override) }
        if node.hasDirectChildText("declare", in: context) { modifiers.append(.declare) }
        return modifiers
    }

    /// Infers a field's type from a direct `new Foo()` construction initializer. Mirrors the
    /// construction check `localBindings` already applies to local declarations.
    private func constructedType(fromFieldValue value: Node?) -> TypeReference? {
        guard let value, value.nodeType == "new_expression",
              let ctor = value.child(byFieldName: "constructor"), ctor.nodeType == "identifier"
        else { return nil }
        return TypeReference(name: text(ctor))
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
                accessLevel: accessMod ?? .internal,
                modifiers: modifiers,
                type: paramType
            ))
        }
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
            accessLevel: isExported ? .public : .internal,
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
            accessLevel: isExported ? .public : .internal,
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
            accessLevel: isExported ? .public : .internal,
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
        // A freestanding function has no enclosing instance, so only file-level type names resolve
        // receivers; its body is still walked so its outgoing calls (bare, `Type.method()`, …) count.
        let callSites = extractCallSites(
            from: node.child(byFieldName: "body"), scope: CallSiteScope(knownTypeNames: declaredTypeNames))
        return Member(
            name: name, kind: .method, accessLevel: isExported ? .public : .internal,
            modifiers: modifiers, type: returnType, parameters: params,
            genericParameters: generics, location: nodeLoc, callSites: callSites)
    }
}
