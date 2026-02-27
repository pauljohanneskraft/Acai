import UMLCore
import UMLTreeSitter

/// Walks a tree-sitter AST (JavaScript or TypeScript) and produces UMLCore model types.
struct JSExtractor: TreeSitterExtracting, CallSiteResolving {
    let context: SourceFileContext
    let isTypeScript: Bool

    var types: [TypeDeclaration] = []
    var relationships: [Relationship] = []
    var freestandingFunctions: [Member] = []
    var currentNamespace: String?

    init(source: String, fileName: String, isTypeScript: Bool) {
        self.context = SourceFileContext(source: source, fileName: fileName)
        self.isTypeScript = isTypeScript
    }

    // MARK: - Shorthands

    /// Builds a qualified ID from an optional namespace and a type name.
    private static func qualifiedId(_ name: String, namespace: String?) -> String {
        namespace.map { "\($0).\(name)" } ?? name
    }

    // MARK: - Public Entry Point

    mutating func extract(from root: Node) -> CodeArtifact {
        walkSourceFile(root)

        // Post-process: qualify type IDs with their namespace so edges resolve correctly.
        for i in types.indices {
            let namespace = types[i].namespace
            let qualifiedTypeName = Self.qualifiedId(types[i].name, namespace: namespace)
            types[i].id = qualifiedTypeName
            types[i].qualifiedName = qualifiedTypeName
        }

        return CodeArtifact(
            metadata: .init(
                sourceLanguage: isTypeScript ? .typeScript : .javaScript,
                filePaths: [context.fileName]
            ),
            types: types,
            relationships: relationships,
            freestandingFunctions: freestandingFunctions
        )
    }
}

// MARK: - Declaration Dispatch & Extraction

extension JSExtractor {

    // MARK: - Program

    mutating func walkSourceFile(_ node: Node) {
        for child in node.children() {
            visitTopLevelNode(child)
        }
        // In JS mode, detect prototype patterns
        if !isTypeScript {
            detectPrototypePatterns(node)
        }
    }

    // MARK: - Top-Level Dispatch

    private mutating func visitTopLevelNode(_ node: Node) {
        guard let nodeType = node.nodeType else { return }
        if nodeType == "export_statement" {
            visitExportStatement(node)
        } else if nodeType == "expression_statement", isTypeScript {
            // tree-sitter-typescript 0.23+: namespace Foo {} → expression_statement → internal_module
            for inner in node.namedChildren() {
                guard let nodeType = inner.nodeType, nodeType == "internal_module" || nodeType == "module" else { continue }
                let (newTypes, newFunctions) = dispatchDeclaration(inner, isExported: false)
                types += newTypes; freestandingFunctions += newFunctions
            }
        } else {
            let (newTypes, newFunctions) = dispatchDeclaration(node, isExported: false)
            types += newTypes; freestandingFunctions += newFunctions
        }
    }

    // MARK: - Export Statement

    private mutating func visitExportStatement(_ node: Node) {
        let isDefault = node.hasDirectChildText("default", in: context)
        let exportDecorators = extractDecorators(node)
        for child in node.children() {
            let (newTypes, newFunctions) = dispatchDeclaration(child, isExported: true, isDefault: isDefault,
                                              decorators: exportDecorators)
            types += newTypes; freestandingFunctions += newFunctions
        }
    }

    // MARK: - Declaration Dispatch

    /// Shared dispatch for top-level nodes, export children, and module body children.
    @discardableResult
    private mutating func dispatchDeclaration(
        _ node: Node,
        isExported: Bool,
        isDefault: Bool = false,
        decorators: [String] = [],
        namespace: String? = nil
    ) -> (types: [TypeDeclaration], functions: [Member]) {
        guard let nodeType = node.nodeType else { return ([], []) }
        var typeDecl: TypeDeclaration?
        switch nodeType {
        case "class_declaration", "class":
            typeDecl = extractClassLikeDeclaration(node, isExported: isExported, isDefault: isDefault)
        case "abstract_class_declaration" where isTypeScript:
            typeDecl = extractClassLikeDeclaration(node, isExported: isExported,
                                                   isDefault: isDefault, isAbstract: true)
        case "interface_declaration" where isTypeScript:
            typeDecl = extractInterfaceDeclaration(node, isExported: isExported)
        case "type_alias_declaration" where isTypeScript:
            typeDecl = extractTypeAliasDeclaration(node, isExported: isExported)
        case "enum_declaration" where isTypeScript:
            typeDecl = extractEnumDeclaration(node, isExported: isExported)
        case "module" where isTypeScript, "internal_module" where isTypeScript:
            var result: [TypeDeclaration] = []
            for var declaration in extractModule(node, isExported: isExported) {
                declaration.annotations.append(contentsOf: decorators)
                if let namespace = namespace { declaration.namespace = namespace }
                result.append(declaration)
            }
            return (result, [])
        case "function_declaration":
            return ([], [extractFunctionDeclaration(node, isExported: isExported)])
        default:
            return ([], [])
        }
        if var decl = typeDecl {
            decl.annotations.append(contentsOf: decorators)
            if let namespace = namespace { decl.namespace = namespace }
            return ([decl], [])
        }
        return ([], [])
    }

    // MARK: - Class Declaration

    private mutating func extractClassLikeDeclaration(
        _ node: Node, isExported: Bool, isDefault: Bool, isAbstract: Bool = false
    ) -> TypeDeclaration {
        let nodeLoc = loc(node)
        var name = node.child(byFieldName: "name").map { text($0) } ?? ""
        if name.isEmpty { name = isDefault ? "default" : "_Anonymous" }

        let modifiers: [Modifier] = isAbstract ? [.abstract] : []
        var annotations = extractDecorators(node)
        if isDefault { annotations.append("default") }

        let generics = isTypeScript ? extractTypeParameters(node) : []
        let (inherited, rels) = extractClassHeritage(node, className: name)
        relationships.append(contentsOf: rels)

        var typeDecl = TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class,
            accessLevel: isExported ? .public : nil,
            modifiers: modifiers,
            genericParameters: generics,
            inheritedTypes: inherited,
            annotations: annotations,
            location: nodeLoc
        )

        if let body = node.child(byFieldName: "body") {
            parseClassBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Class Heritage (extends/implements)

    private func extractClassHeritage(_ node: Node, className: String) -> ([TypeReference], [Relationship]) {
        var inherited: [TypeReference] = []
        var rels: [Relationship] = []

        for child in node.children() {
            if child.nodeType == "class_heritage" {
                for heritageChild in child.children() {
                    collectHeritageClause(heritageChild, className: className,
                                         inherited: &inherited, rels: &rels)
                }
            }
            collectHeritageClause(child, className: className,
                                 inherited: &inherited, rels: &rels)
        }
        return (inherited, rels)
    }

    private func collectHeritageClause(
        _ node: Node, className: String,
        inherited: inout [TypeReference], rels: inout [Relationship]
    ) {
        switch node.nodeType {
        case "extends_clause":
            if let valueNode = node.child(byFieldName: "value") ?? node.namedChildren().first {
                let ref = extractTypeReferenceFromExpression(valueNode)
                inherited.append(ref)
                rels.append(Relationship(kind: .inheritance, source: className, target: ref.name))
            }
        case "implements_clause":
            for typeNode in node.namedChildren() {
                let ref = extractTypeReferenceFromExpression(typeNode)
                inherited.append(ref)
                rels.append(Relationship(kind: .conformance, source: className, target: ref.name))
            }
        default:
            break
        }
    }

    // MARK: - Decorators / Annotations

    private func extractDecorators(_ node: Node) -> [String] {
        var annotations: [String] = []
        for child in node.children() {
            guard child.nodeType == "decorator" else { continue }
            let fullText = text(child)
            if let parenIdx = fullText.firstIndex(of: "(") {
                annotations.append(String(fullText[fullText.startIndex..<parenIdx]))
            } else {
                annotations.append(fullText)
            }
        }
        return annotations
    }
}

// MARK: - Members & Type Extraction

extension JSExtractor {

    // MARK: - Class Body

    private func parseClassBody(_ bodyNode: Node, into typeDecl: inout TypeDeclaration) {
        let knownProperties = buildPropertyMapFromBody(bodyNode)

        for child in bodyNode.children() {
            guard let childType = child.nodeType else { continue }
            switch childType {
            case "method_definition", "abstract_method_definition":
                var member = extractMethodDefinition(child, parentName: typeDecl.name,
                                                     knownProperties: knownProperties)
                if childType == "abstract_method_definition", isTypeScript,
                   !member.modifiers.contains(.abstract) {
                    member.modifiers.append(.abstract)
                }
                if member.kind == .initializer, isTypeScript {
                    extractConstructorParameterProperties(child, into: &typeDecl)
                }
                typeDecl.members.append(member)

            case "field_definition", "public_field_definition":
                typeDecl.members.append(extractFieldDefinition(child))

            case "method_signature" where isTypeScript:
                typeDecl.members.append(extractMethodSignature(child))

            case "property_signature" where isTypeScript:
                typeDecl.members.append(extractPropertySignature(child))

            default:
                break
            }
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

    private func extractMethodDefinition(
        _ node: Node,
        parentName: String,
        knownProperties: [String: String] = [:]
    ) -> Member {
        let nodeLoc = loc(node)
        let nameNode = node.child(byFieldName: "name")
        let name = nameNode.map { text($0) } ?? ""

        var kind: MemberKind = .method
        var accessLevel: AccessLevel?
        var modifiers: [Modifier] = []
        var isComputed = false
        let annotations = extractDecorators(node)

        for child in node.children() {
            switch text(child) {
            case "static":                      modifiers.append(.static)
            case "get", "set":                  isComputed = true; kind = .property
            case "async":                       modifiers.append(.async)
            case "abstract" where isTypeScript: modifiers.append(.abstract)
            case "override":                    modifiers.append(.override)
            default:                            break
            }
        }

        if isTypeScript { accessLevel = extractAccessibilityModifier(node) }
        if name.hasPrefix("#") { accessLevel = .private }
        if name == "constructor" { kind = .initializer }
        if isTypeScript && node.hasDirectChildText("readonly", in: context) { modifiers.append(.readonly) }

        let generics = isTypeScript ? extractTypeParameters(node) : []
        let params = node.child(byFieldName: "parameters").map { extractParameters($0) } ?? []
        let returnType = isTypeScript ? extractReturnTypeAnnotation(node) : nil

        let callSites = extractCallSites(from: node.child(byFieldName: "body"),
                                         knownProperties: knownProperties)

        return Member(
            name: name.isEmpty ? "_anonymous" : name,
            kind: kind,
            accessLevel: accessLevel,
            modifiers: modifiers,
            type: returnType,
            parameters: params,
            genericParameters: generics,
            isComputed: isComputed,
            annotations: annotations,
            location: nodeLoc,
            callSites: callSites
        )
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
            location: nodeLoc
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

    private mutating func extractInterfaceDeclaration(_ node: Node, isExported: Bool) -> TypeDeclaration {
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

    private func extractTypeAliasDeclaration(_ node: Node, isExported: Bool) -> TypeDeclaration {
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

    private func extractEnumDeclaration(_ node: Node, isExported: Bool) -> TypeDeclaration {
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

    private mutating func extractModule(_ node: Node, isExported: Bool) -> [TypeDeclaration] {
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
                        let (newTypes, newFunctions) = dispatchDeclaration(exportChild, isExported: true, isDefault: isDefault,
                                                           decorators: exportDecorators, namespace: name)
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

    private func extractFunctionDeclaration(_ node: Node, isExported: Bool) -> Member {
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

// MARK: - Parameters, Types & Utilities

extension JSExtractor {

    // MARK: - Call Site Extraction

    /// Matches JS/TS `call_expression { function: member_expression { object, property } }`.
    ///
    /// Handles:
    /// - `receiver.method(args)` — `object` is an `identifier`.
    /// - `this.receiver.method(args)` — `object` is a `member_expression` whose own
    ///   `object` is a `this` node.
    func resolveCallSite(_ node: Node, knownProperties: [String: String]) -> CallSite? {
        guard node.nodeType == "call_expression",
              let funcNode = node.child(byFieldName: "function"),
              funcNode.nodeType == "member_expression",
              let propertyNode = funcNode.child(byFieldName: "property"),
              let objectNode   = funcNode.child(byFieldName: "object")
        else { return nil }

        let methodName = text(propertyNode)
        var receiverVarName: String?

        if objectNode.nodeType == "identifier" {
            receiverVarName = text(objectNode)
        } else if objectNode.nodeType == "member_expression",
                  objectNode.child(byFieldName: "object")?.nodeType == "this",
                  let propNode = objectNode.child(byFieldName: "property") {
            receiverVarName = text(propNode)
        }

        guard let varName = receiverVarName,
              let receiverType = knownProperties[varName]
        else { return nil }

        return CallSite(receiverType: receiverType, methodName: methodName, location: loc(node))
    }

    // MARK: - Parameters

    private func extractParameters(_ node: Node) -> [Parameter] {
        var params: [Parameter] = []
        for child in node.children() {
            guard let childType = child.nodeType else { continue }
            switch childType {
            case "formal_parameter", "required_parameter", "optional_parameter":
                params.append(extractSingleParameter(child, isOptional: childType == "optional_parameter"))
            case "rest_pattern", "rest_element":
                var param = extractRestParameter(child)
                param.isVariadic = true
                params.append(param)
            case "identifier":
                params.append(Parameter(internalName: text(child)))
            case "assignment_pattern":
                params.append(extractAssignmentParameter(child))
            case "destructuring_pattern", "array_pattern", "object_pattern":
                params.append(Parameter(internalName: text(child)))
            default:
                break
            }
        }
        return params
    }

    private func extractSingleParameter(_ node: Node, isOptional: Bool) -> Parameter {
        let name: String
        if let patternNode = node.child(byFieldName: "pattern") {
            name = text(patternNode)
        } else {
            name = extractParameterName(node)
        }

        var paramType: TypeReference?
        if isTypeScript {
            paramType = extractTypeAnnotation(node)
        }

        if isOptional { paramType?.isOptional = true }

        let defaultValue: String? = node.child(byFieldName: "value").map { text($0) }

        var modifiers: [Modifier] = []
        if node.hasDirectChildText("readonly", in: context) {
            modifiers.append(.readonly)
        }

        return Parameter(internalName: name, type: paramType, defaultValue: defaultValue, modifiers: modifiers)
    }

    private func extractRestParameter(_ node: Node) -> Parameter {
        var name = ""
        for child in node.namedChildren() where child.nodeType == "identifier" {
            name = text(child)
            break
        }
        if name.isEmpty {
            if let patternNode = node.child(byFieldName: "pattern") {
                name = text(patternNode)
            } else {
                name = text(node).replacingOccurrences(of: "...", with: "")
            }
        }

        var paramType: TypeReference?
        if isTypeScript { paramType = extractTypeAnnotation(node) }

        return Parameter(internalName: name, type: paramType, isVariadic: true)
    }

    private func extractAssignmentParameter(_ node: Node) -> Parameter {
        let name = node.child(byFieldName: "left").map { text($0) } ?? ""
        let defaultValue = node.child(byFieldName: "right").map { text($0) }
        return Parameter(internalName: name, defaultValue: defaultValue)
    }

    private func extractParameterName(_ node: Node) -> String {
        if let pattern = node.child(byFieldName: "pattern") {
            return text(pattern)
        }
        for child in node.children() where child.nodeType == "identifier" {
            return text(child)
        }
        return ""
    }

    // MARK: - Type Annotations (TypeScript)

    private func extractTypeAnnotation(_ node: Node) -> TypeReference? {
        guard isTypeScript else { return nil }
        guard let typeAnnotation = node.firstChild(withType: "type_annotation") else { return nil }
        if let typeNode = typeAnnotation.namedChildren().first {
            return extractTypeReference(typeNode)
        }
        return nil
    }

    private func extractReturnTypeAnnotation(_ node: Node) -> TypeReference? {
        guard isTypeScript else { return nil }
        if let returnType = node.child(byFieldName: "return_type") {
            if let typeNode = returnType.namedChildren().first {
                return extractTypeReference(typeNode)
            }
            return extractTypeReference(returnType)
        }
        return extractTypeAnnotation(node)
    }

    // MARK: - Type Reference Extraction

    private func extractTypeReference(_ node: Node) -> TypeReference {
        guard let nodeType = node.nodeType else {
            return TypeReference(name: text(node))
        }

        switch nodeType {
        case "predefined_type", "type_identifier", "identifier",
             "union_type", "intersection_type", "function_type", "literal_type",
             "tuple_type", "conditional_type", "index_type_query", "mapped_type",
             "type_query", "object_type", "template_literal_type", "existential_type",
             "nested_type_identifier", "member_expression", "this_type":
            return TypeReference(name: text(node))

        case "generic_type":
            let nameNode = node.child(byFieldName: "name") ?? node.namedChildren().first
            let name = nameNode.map { text($0) } ?? text(node)
            var genericArgs: [TypeReference] = []
            if let typeArgs = node.child(byFieldName: "type_arguments") ?? node.firstChild(withType: "type_arguments") {
                for argChild in typeArgs.namedChildren() {
                    genericArgs.append(extractTypeReference(argChild))
                }
            }
            return TypeReference(name: name, genericArguments: genericArgs)

        case "array_type":
            if let elementType = node.namedChildren().first {
                let inner = extractTypeReference(elementType)
                return TypeReference(name: inner.name, genericArguments: inner.genericArguments, isArray: true)
            }
            return TypeReference(name: text(node), isArray: true)

        case "parenthesized_type":
            if let inner = node.namedChildren().first { return extractTypeReference(inner) }
            return TypeReference(name: text(node))

        case "readonly_type":
            if let inner = node.namedChildren().first { return extractTypeReference(inner) }
            return TypeReference(name: text(node))

        case "flow_maybe_type":
            if let inner = node.namedChildren().first {
                var ref = extractTypeReference(inner)
                ref.isOptional = true
                return ref
            }
            return TypeReference(name: text(node), isOptional: true)

        default:
            return TypeReference(name: text(node))
        }
    }

    private func extractTypeReferenceFromExpression(_ node: Node) -> TypeReference {
        switch node.nodeType ?? "" {
        case "identifier", "type_identifier", "property_identifier":
            return TypeReference(name: text(node))
        case "generic_type":
            return extractTypeReference(node)
        default:
            return TypeReference(name: text(node))
        }
    }

    // MARK: - Generic / Type Parameters

    private func extractTypeParameters(_ node: Node) -> [GenericParameter] {
        guard let typeParamsNode = node.child(byFieldName: "type_parameters")
                ?? node.firstChild(withType: "type_parameters") else {
            return []
        }

        var params: [GenericParameter] = []
        for child in typeParamsNode.namedChildren() {
            guard child.nodeType == "type_parameter" else { continue }
            let nameNode = child.child(byFieldName: "name") ?? child.namedChildren().first
            let name = nameNode.map { text($0) } ?? ""
            guard !name.isEmpty else { continue }

            var constraints: [GenericConstraint] = []
            if let constraintNode = child.child(byFieldName: "constraint") {
                let constraintType = extractTypeReference(constraintNode)
                constraints.append(GenericConstraint(kind: .conformance, type: constraintType))
            }
            params.append(GenericParameter(name: name, constraints: constraints))
        }
        return params
    }

    // MARK: - Accessibility Modifier

    private static let accessLevelMap: [String: AccessLevel] = [
        "public": .public, "private": .private, "protected": .protected
    ]

    private func extractAccessibilityModifier(_ node: Node) -> AccessLevel? {
        for child in node.children() where child.nodeType == "accessibility_modifier" {
            if let level = Self.accessLevelMap[text(child)] { return level }
        }
        for child in node.children() where child.nodeType != "type_identifier" {
            if let level = Self.accessLevelMap[text(child)] { return level }
        }
        return nil
    }

    // MARK: - Prototype Pattern Detection (JS only)

    private mutating func detectPrototypePatterns(_ root: Node) {
        var prototypeAssignments: [(className: String, memberName: String, node: Node)] = []

        for child in root.children() {
            guard child.nodeType == "expression_statement" else { continue }
            guard let expr = child.namedChildren().first, expr.nodeType == "assignment_expression" else { continue }
            guard let leftNode = expr.child(byFieldName: "left"),
                  leftNode.nodeType == "member_expression" else { continue }
            let leftText = text(leftNode)
            if let protoRange = leftText.range(of: ".prototype.") {
                let className = String(leftText[leftText.startIndex..<protoRange.lowerBound])
                let memberName = String(leftText[protoRange.upperBound...])
                if !className.isEmpty && !memberName.isEmpty {
                    prototypeAssignments.append((className, memberName, expr))
                }
            }
        }

        for assignment in prototypeAssignments {
            ensureTypeExists(name: assignment.className)
            let rightNode = assignment.node.child(byFieldName: "right")
            var isFunction = false
            var params: [Parameter] = []
            var modifiers: [Modifier] = []

            if let rightNode = rightNode {
                let rightType = rightNode.nodeType ?? ""
                if rightType == "function_expression" || rightType == "function" || rightType == "arrow_function" {
                    isFunction = true
                    if rightNode.hasDirectChildText("async", in: context) { modifiers.append(.async) }
                    if let paramsNode = rightNode.child(byFieldName: "parameters") {
                        params = extractParameters(paramsNode)
                    }
                }
            }

            if let index = types.firstIndex(where: { $0.name == assignment.className }) {
                if isFunction {
                    types[index].members.append(Member(
                        name: assignment.memberName, kind: .method,
                        modifiers: modifiers, parameters: params
                    ))
                } else {
                    types[index].members.append(Member(name: assignment.memberName, kind: .property))
                }
            }
        }
    }

    private mutating func ensureTypeExists(name: String) {
        if !types.contains(where: { $0.name == name }) {
            types.append(TypeDeclaration(id: name, name: name, qualifiedName: name, kind: .class))
        }
    }
}
