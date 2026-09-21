import AcaiCore
import AcaiTreeSitter

// MARK: - JSMemberExtractor

/// Shapes a `Member` value from an already-parsed method/field/signature node plus its
/// already-resolved pieces (parameters, return type, call sites, assignments, field reads) — mirrors
/// `AcaiPython`'s `PythonMemberExtractor`: this never resolves a call site or reads `JSExtractor`'s
/// declaration state itself, it only builds the value from what the caller already computed.
struct JSMemberExtractor {
    let context: SourceFileContext
    let isTypeScript: Bool
    let typeReferences: JSTypeReferenceResolver
    let parameterExtractor: JSParameterExtractor

    /// JS/TS structural decision-point node types for cyclomatic complexity.
    static let branchNodeKinds: Set<String> = [
        "if_statement", "for_statement", "for_in_statement", "while_statement", "do_statement",
        "catch_clause", "switch_case"
    ]

    private static let methodKeywordModifiers: [String: Modifier] = [
        "static": .static, "async": .async, "override": .override
    ]

    private static let functionNodeTypes: Set<String> = [
        "function_expression", "function", "arrow_function"
    ]

    /// Fully resolved pieces a method/function body contributes to its `Member`.
    struct References {
        var callSites: [CallSite] = []
        var assignments: [VariableAssignment] = []
        var fieldReads: [FieldAccess] = []
        var referencedTypeNames: [String] = []
        var cyclomaticComplexity: Int?
    }

    /// The pieces a field or global variable's initializer contributes.
    struct ValueReferences {
        var callSites: [CallSite] = []
        var initialValue: VariableAssignment.Value?
        var referencedTypeNames: [String] = []
    }

    private struct MethodSignatureInfo {
        var kind: MemberKind
        var accessLevel: AccessLevel?
        var modifiers: [Modifier]
        var isComputed: Bool
    }

    // MARK: - Method Definition

    func methodDefinition(
        _ node: Node,
        generics: [GenericParameter],
        parameters: [Parameter],
        returnType: TypeReference?,
        references: References
    ) -> Member {
        let nameNode = node.child(byFieldName: "name")
        let name = nameNode.map { $0.text(in: context) } ?? ""
        let annotations = decorators(node)
        let sig = methodKindAndModifiers(node, name: name)

        return Member(
            name: name.isEmpty ? "_anonymous" : name,
            kind: sig.kind,
            accessLevel: sig.accessLevel ?? .internal,
            modifiers: sig.modifiers,
            type: returnType,
            parameters: parameters,
            genericParameters: generics,
            isComputed: sig.isComputed,
            annotations: annotations,
            location: node.location(in: context),
            callSites: references.callSites,
            assignments: references.assignments,
            fieldReads: references.fieldReads,
            referencedTypeNames: references.referencedTypeNames,
            cyclomaticComplexity: references.cyclomaticComplexity
        )
    }

    private func methodKindAndModifiers(_ node: Node, name: String) -> MethodSignatureInfo {
        var kind: MemberKind = .method
        var modifiers: [Modifier] = []
        var isComputed = false

        for child in node.children() {
            let childText = child.text(in: context)
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
        if isTypeScript { accessLevel = typeReferences.extractAccessibilityModifier(node) }
        if name.hasPrefix("#") { accessLevel = .private }
        if name == "constructor" { kind = .initializer }
        if isTypeScript, node.hasDirectChildText("readonly", in: context) {
            modifiers.append(.readonly)
        }

        return MethodSignatureInfo(kind: kind, accessLevel: accessLevel, modifiers: modifiers, isComputed: isComputed)
    }

    // MARK: - Class Body Pre-Pass Maps

    /// `fieldName → typeName` from the class body's direct field declarations plus (TypeScript)
    /// constructor parameter properties, so a same-type method call through a typed stored property
    /// (`this.cache.process()`) resolves. Built before member extraction, so it can't itself depend
    /// on the scope it feeds.
    func propertyMap(fromBody bodyNode: Node) -> [String: String] {
        var map: [String: String] = [:]

        for child in bodyNode.children() {
            guard let childType = child.nodeType else { continue }

            if childType == "field_definition" || childType == "public_field_definition" {
                let member = fieldDefinition(child, references: ValueReferences())
                if !member.modifiers.contains(.static), let typeName = member.type?.name {
                    map[member.name] = typeName
                }
            } else if childType == "method_definition", isTypeScript,
                      child.child(byFieldName: "name").map({ $0.text(in: context) }) == "constructor" {
                for member in constructorParameterProperties(child) {
                    if !member.name.isEmpty, let typeName = member.type?.name {
                        map[member.name] = typeName
                    }
                }
            }
        }
        return map
    }

    /// A `methodName → returnTypeName` map from the class body's direct `method_definition` children
    /// (TypeScript only — JS has no return-type annotations), so a same-type method call with an
    /// unambiguous return type can seed a local's type. Overloaded names with differing return types
    /// are dropped rather than guessed.
    func methodReturnTypeMap(fromBody bodyNode: Node) -> [String: String] {
        guard isTypeScript else { return [:] }
        var returnTypes = UnambiguousTypeNames()
        for child in bodyNode.children() where child.nodeType == "method_definition" {
            guard let nameNode = child.child(byFieldName: "name"),
                  let returnType = typeReferences.extractReturnTypeAnnotation(child)
            else { continue }
            returnTypes.record(returnType.name, for: nameNode.text(in: context))
        }
        return returnTypes.resolved
    }

    // MARK: - Field Definition

    func fieldDefinition(_ node: Node, references: ValueReferences) -> Member {
        let nameNode = node.child(byFieldName: "property") ?? node.child(byFieldName: "name")
        let name = nameNode.map { $0.text(in: context) } ?? ""

        var accessLevel: AccessLevel? = name.hasPrefix("#") ? .private : nil
        if isTypeScript, let acc = typeReferences.extractAccessibilityModifier(node) {
            accessLevel = acc
        }

        var propType = isTypeScript ? typeReferences.extractTypeAnnotation(node) : nil
        // No (or no TypeScript) annotation — infer from a direct construction initializer (`private
        // cache = new ImageCache();`), same heuristic `localBindings` applies to locals. Without
        // this, calls through a composed collaborator field (`this.cache.process()`) can't resolve.
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
            annotations: decorators(node),
            location: node.location(in: context),
            callSites: references.callSites,
            initialValue: references.initialValue,
            referencedTypeNames: references.referencedTypeNames
        )
    }

    /// The type a field or global variable's `new Foo()` initializer proves, absent a TypeScript
    /// annotation. Mirrors the construction check `JSCallSiteSyntax.localBindings` applies to locals.
    func constructedType(fromFieldValue value: Node?) -> TypeReference? {
        guard let value, value.nodeType == "new_expression",
              let ctor = value.child(byFieldName: "constructor"), ctor.nodeType == "identifier"
        else { return nil }
        return TypeReference(name: ctor.text(in: context))
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

    // MARK: - Top-Level Variable Declaration

    /// A top-level (module-scope) `const`/`let`/`var` declarator, or one inside a TS `namespace`
    /// body. Reuses the same type-inference and value-classification `fieldDefinition` applies to a
    /// class field, since JS/TS has no separate grammar node for global vs. instance state.
    func globalVariable(_ node: Node, name: String, isExported: Bool, references: ValueReferences) -> Member {
        let value = node.child(byFieldName: "value")

        var propType = isTypeScript ? typeReferences.extractTypeAnnotation(node) : nil
        if propType == nil {
            propType = constructedType(fromFieldValue: value)
        }

        return Member(
            name: name,
            kind: .property,
            accessLevel: isExported ? .public : .internal,
            type: propType,
            location: node.location(in: context),
            callSites: references.callSites,
            initialValue: references.initialValue,
            referencedTypeNames: references.referencedTypeNames
        )
    }

    // MARK: - Interface Members (TypeScript)

    func propertySignature(_ node: Node) -> Member {
        let nameNode = node.child(byFieldName: "name")
        let name = nameNode.map { $0.text(in: context) } ?? ""

        var accessLevel: AccessLevel?
        var modifiers: [Modifier] = []

        if let acc = typeReferences.extractAccessibilityModifier(node) {
            accessLevel = acc
        }
        if node.hasDirectChildText("readonly", in: context) {
            modifiers.append(.readonly)
        }

        var propType = typeReferences.extractTypeAnnotation(node)
        if node.hasDirectChildText("?", in: context) {
            propType?.isOptional = true
        }

        return Member(
            name: name, kind: .property,
            accessLevel: accessLevel ?? .internal,
            modifiers: modifiers,
            type: propType,
            location: node.location(in: context)
        )
    }

    func methodSignature(_ node: Node) -> Member {
        let nameNode = node.child(byFieldName: "name")
        let name = nameNode.map { $0.text(in: context) } ?? ""

        let accessLevel = typeReferences.extractAccessibilityModifier(node)
        let generics = typeReferences.extractTypeParameters(node)
        let params: [Parameter]
        if let paramsNode = node.child(byFieldName: "parameters") {
            params = parameterExtractor.parameters(paramsNode)
        } else {
            params = []
        }
        let returnType = typeReferences.extractReturnTypeAnnotation(node)

        return Member(
            name: name, kind: .method,
            accessLevel: accessLevel ?? .internal,
            type: returnType,
            parameters: params,
            genericParameters: generics,
            location: node.location(in: context)
        )
    }

    // MARK: - Constructor Parameter Properties (TypeScript)

    func constructorParameterProperties(_ ctorNode: Node) -> [Member] {
        guard let paramsNode = ctorNode.child(byFieldName: "parameters") else { return [] }
        var members: [Member] = []
        for child in paramsNode.children() {
            guard let childType = child.nodeType else { continue }
            guard childType == "required_parameter" || childType == "optional_parameter" else { continue }

            let accessMod = typeReferences.extractAccessibilityModifier(child)
            let hasReadonly = child.hasDirectChildText("readonly", in: context)
            guard accessMod != nil || hasReadonly else { continue }

            let paramName = parameterExtractor.parameterName(child)
            var modifiers: [Modifier] = []
            if hasReadonly { modifiers.append(.readonly) }

            let paramType = typeReferences.extractTypeAnnotation(child)
            members.append(Member(
                name: paramName,
                kind: .property,
                accessLevel: accessMod ?? .internal,
                modifiers: modifiers,
                type: paramType
            ))
        }
        return members
    }

    // MARK: - Prototype Pattern Members (JS only)

    func prototypeMember(name memberName: String, assignedValue rightNode: Node?) -> Member {
        guard let rightNode, let rightType = rightNode.nodeType, Self.functionNodeTypes.contains(rightType) else {
            return Member(name: memberName, kind: .property, accessLevel: .internal)
        }
        var modifiers: [Modifier] = []
        if rightNode.hasDirectChildText("async", in: context) { modifiers.append(.async) }
        let params = rightNode.child(byFieldName: "parameters").map { parameterExtractor.parameters($0) } ?? []
        return Member(name: memberName, kind: .method, accessLevel: .internal, modifiers: modifiers, parameters: params)
    }

    // MARK: - Decorators / Annotations

    func decorators(_ node: Node) -> [String] {
        var annotations: [String] = []
        for child in node.children() {
            guard child.nodeType == "decorator" else { continue }
            let fullText = child.text(in: context)
            if let parenIdx = fullText.firstIndex(of: "(") {
                annotations.append(String(fullText[fullText.startIndex..<parenIdx]))
            } else {
                annotations.append(fullText)
            }
        }
        return annotations
    }
}
