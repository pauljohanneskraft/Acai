import AcaiCore
import AcaiTreeSitter

struct PythonExtractor: TreeSitterExtracting, CallSiteResolving {
    let context: SourceFileContext
    let typeReferenceResolver: PythonTypeReferenceResolver
    let baseClassResolver: PythonBaseClassResolver
    let parameterExtractor: PythonParameterExtractor
    let memberExtractor: PythonMemberExtractor
    let typeDeclarationExtractor: PythonTypeDeclarationExtractor

    var types: [TypeDeclaration] = []
    var relationships: [Relationship] = []
    var freestandingFunctions: [Member] = []
    var globalVariables: [Member] = []
    var currentNamespace: String?
    var declaredTypeNames: Set<String> = []
    var topLevelCallSites: [CallSite] = []

    init(source: String, fileName: String) {
        let context = SourceFileContext(source: source, fileName: fileName)
        let typeReferenceResolver = PythonTypeReferenceResolver(context: context)
        let baseClassResolver = PythonBaseClassResolver(context: context, typeReferences: typeReferenceResolver)

        self.context = context
        self.typeReferenceResolver = typeReferenceResolver
        self.baseClassResolver = baseClassResolver
        self.parameterExtractor = PythonParameterExtractor(context: context, typeReferences: typeReferenceResolver)
        self.memberExtractor = PythonMemberExtractor(context: context, typeReferences: typeReferenceResolver)
        self.typeDeclarationExtractor = PythonTypeDeclarationExtractor(
            context: context, baseClassResolver: baseClassResolver
        )
    }

    // MARK: - Public Entry Point

    mutating func extract(from root: Node) -> CodeArtifact {
        declaredTypeNames = collectDeclaredTypeNames(
            from: root,
            declarationNodeTypes: ["class_definition"],
            name: { $0.child(byFieldName: "name").map { self.text($0) } }
        )
        walkSourceFile(root)
        resolveRelationshipNames()
        return buildArtifact(language: .python)
    }

    // MARK: - Access Level (naming convention)

    /// Python has no access keywords; visibility is conveyed by leading underscores (dunders are
    /// public, `__x` is name-mangled private, `_x` is protected).
    func accessLevel(forName name: String) -> AccessLevel {
        if name.hasPrefix("__") && name.hasSuffix("__") { return .public }
        if name.hasPrefix("__") { return .private }
        if name.hasPrefix("_") { return .protected }
        return .public
    }
}

// MARK: - Top-level traversal

extension PythonExtractor {

    mutating func walkSourceFile(_ node: Node) {
        for child in node.children() {
            visitTopLevel(child)
        }
        if !topLevelCallSites.isEmpty {
            freestandingFunctions.append(Member(
                name: "<top-level>", kind: .method, accessLevel: .public, callSites: topLevelCallSites))
        }
    }

    private mutating func visitTopLevel(_ node: Node) {
        switch node.nodeType {
        case "class_definition":
            types.append(extractClass(node, decorators: []))
        case "function_definition":
            freestandingFunctions.append(extractCallable(node, decorators: [], scope: moduleScope()))
        case "decorated_definition":
            visitDecorated(node)
        case "expression_statement":
            for assign in node.namedChildren() where assign.nodeType == "assignment" {
                if let member = extractModuleVariable(assign) {
                    globalVariables.append(member)
                }
            }
            // A bare top-level call (`main()`) has no caller to attach to, so it's collected
            // separately and given a synthetic reachable member in `walkSourceFile`.
            topLevelCallSites.append(contentsOf: extractCallSites(from: node, scope: moduleScope()))
        case "if_statement":
            // Covers the idiomatic `if __name__ == "__main__": main()` entry point.
            topLevelCallSites.append(contentsOf: extractCallSites(from: node, scope: moduleScope()))
        default:
            break
        }
    }

    private mutating func visitDecorated(_ node: Node) {
        let decorators = extractDecorators(node)
        guard let def = node.child(byFieldName: "definition") else { return }
        switch def.nodeType {
        case "class_definition":
            types.append(extractClass(def, decorators: decorators))
        case "function_definition":
            freestandingFunctions.append(extractCallable(def, decorators: decorators, scope: moduleScope()))
        default:
            break
        }
    }

    func moduleScope() -> CallSiteScope {
        CallSiteScope(knownTypeNames: declaredTypeNames)
    }

    func extractModuleVariable(_ assign: Node) -> Member? {
        guard let left = assign.child(byFieldName: "left"), left.nodeType == "identifier" else { return nil }
        let name = text(left)
        let type = assign.child(byFieldName: "type").flatMap { typeReferenceResolver.resolve(fromTypeField: $0) }
        let initial = assign.child(byFieldName: "right").map { classifyValue($0) }
        return Member(
            name: name,
            kind: .property,
            accessLevel: accessLevel(forName: name),
            type: type,
            location: loc(assign),
            initialValue: initial
        )
    }

    // MARK: - Decorators

    /// Bare decorator names, e.g. `@app.route(...)` → `"app.route"`, `@dataclass` → `"dataclass"`.
    func extractDecorators(_ node: Node) -> [String] {
        var result: [String] = []
        for child in node.children() where child.nodeType == "decorator" {
            var raw = text(child)
            if raw.hasPrefix("@") { raw.removeFirst() }
            if let paren = raw.firstIndex(of: "(") { raw = String(raw[raw.startIndex..<paren]) }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { result.append(trimmed) }
        }
        return result
    }
}

// MARK: - Class extraction

extension PythonExtractor {

    mutating func extractClass(_ node: Node, decorators: [String]) -> TypeDeclaration {
        let name = node.child(byFieldName: "name").map { text($0) } ?? "_Anonymous"
        // Namespaced so a nested `Inner` doesn't collide with a top-level `Inner`.
        let qualified = qualifiedName(name)
        let bases = baseClassResolver.bases(for: node, className: qualified)
        relationships.append(contentsOf: bases.relationships)

        var decl = typeDeclarationExtractor.declaration(
            for: node,
            signature: .init(
                name: name, qualifiedName: qualified, decorators: decorators, bases: bases,
                accessLevel: accessLevel(forName: name)
            )
        )

        if let body = node.child(byFieldName: "body") {
            let savedNamespace = currentNamespace
            currentNamespace = qualified
            defer { currentNamespace = savedNamespace }
            if decl.kind == .enum {
                parseEnumBody(body, into: &decl)
            } else {
                parseClassBody(body, into: &decl)
            }
        }

        let hasAbstractMember = decl.members.contains { $0.modifiers.contains(.abstract) }
        if hasAbstractMember || baseClassResolver.hasAbstractBase(in: bases.allNames) {
            if !decl.modifiers.contains(.abstract) { decl.modifiers.append(.abstract) }
        }
        return decl
    }

    // MARK: - Enum body

    /// Class-body `NAME = value` assignments are enum cases here, not properties.
    private mutating func parseEnumBody(_ body: Node, into decl: inout TypeDeclaration) {
        let scope = CallSiteScope(knownTypeNames: declaredTypeNames)
        for child in body.namedChildren() {
            switch child.nodeType {
            case "expression_statement":
                for assign in child.namedChildren() where assign.nodeType == "assignment" {
                    guard let left = assign.child(byFieldName: "left"), left.nodeType == "identifier" else { continue }
                    let rawValue = assign.child(byFieldName: "right").map { text($0) }
                    decl.enumCases.append(EnumCase(name: text(left), rawValue: rawValue, location: loc(assign)))
                }
            case "function_definition":
                decl.members.append(extractCallable(child, decorators: [], scope: scope))
            case "decorated_definition":
                if let def = child.child(byFieldName: "definition"), def.nodeType == "function_definition" {
                    decl.members.append(extractCallable(def, decorators: extractDecorators(child), scope: scope))
                }
            default:
                break
            }
        }
    }
}

// MARK: - Members (methods, fields, self.x synthesis)

extension PythonExtractor {

    mutating func parseClassBody(_ body: Node, into decl: inout TypeDeclaration) {
        for child in body.namedChildren() {
            if child.nodeType == "class_definition" {
                decl.nestedTypes.append(extractClass(child, decorators: []))
            } else if child.nodeType == "decorated_definition",
                      let def = child.child(byFieldName: "definition"), def.nodeType == "class_definition" {
                decl.nestedTypes.append(extractClass(def, decorators: extractDecorators(child)))
            }
        }

        let methodNodes = collectMethodNodes(body)

        // A class-body initializer can't reference `self`, so file-level type names are the only
        // resolvable receivers.
        var fields = collectClassBodyFields(body, scope: CallSiteScope(knownTypeNames: declaredTypeNames))
        let existing = Set(fields.map(\.name))
        fields.append(contentsOf: memberExtractor.synthesizeSelfFields(
            fromMethods: methodNodes, existing: existing, declaredTypeNames: declaredTypeNames,
            accessLevel: accessLevel(forName:)
        ))

        let scope = CallSiteScope(
            knownProperties: memberExtractor.propertyMap(from: fields),
            knownTypeNames: declaredTypeNames,
            // Python fields are frequently untyped (`self.x = …`), so the typed `propertyMap` misses
            // them — pass every field name so field-read capture (issue #111) sees them all.
            knownPropertyNames: Set(fields.map(\.name)),
            knownMethodReturnTypes: memberExtractor.methodReturnTypeMap(fromMethodNodes: methodNodes)
        )

        decl.members.append(contentsOf: fields)
        for method in methodNodes {
            decl.members.append(extractCallable(method.node, decorators: method.decorators, scope: scope))
        }
    }

    func collectMethodNodes(_ body: Node) -> [(node: Node, decorators: [String])] {
        var result: [(node: Node, decorators: [String])] = []
        for child in body.namedChildren() {
            if child.nodeType == "function_definition" {
                result.append((child, []))
            } else if child.nodeType == "decorated_definition",
                      let def = child.child(byFieldName: "definition"), def.nodeType == "function_definition" {
                result.append((def, extractDecorators(child)))
            }
        }
        return result
    }

    // MARK: - Class-body fields

    private func collectClassBodyFields(_ body: Node, scope: CallSiteScope) -> [Member] {
        let resolver = typeReferenceResolver
        var fields: [Member] = []
        for child in body.namedChildren() where child.nodeType == "expression_statement" {
            for assign in child.namedChildren() where assign.nodeType == "assignment" {
                guard let left = assign.child(byFieldName: "left"), left.nodeType == "identifier" else { continue }
                let name = text(left)
                let type = assign.child(byFieldName: "type").flatMap { resolver.resolve(fromTypeField: $0) }
                let initial = assign.child(byFieldName: "right").map { classifyValue($0) }
                fields.append(memberExtractor.field(
                    name: name,
                    type: type,
                    accessLevel: accessLevel(forName: name),
                    location: loc(assign),
                    callSites: extractCallSites(from: assign.child(byFieldName: "right"), scope: scope),
                    initialValue: initial,
                    referencedTypeNames: referencedTypeNames(in: assign.child(byFieldName: "right"))
                ))
            }
        }
        return fields
    }

    // MARK: - Methods & functions

    func extractCallable(_ node: Node, decorators: [String], scope: CallSiteScope) -> Member {
        let params = node.child(byFieldName: "parameters").map { parameterExtractor.parameters($0) } ?? []
        let returnType = node.child(byFieldName: "return_type")
            .flatMap { typeReferenceResolver.resolve(fromTypeField: $0) }
        let name = node.child(byFieldName: "name").map { text($0) } ?? "_anonymous"
        let body = node.child(byFieldName: "body")

        return memberExtractor.callable(
            node,
            signature: .init(
                decorators: decorators, parameters: params, returnType: returnType,
                accessLevel: accessLevel(forName: name)
            ),
            references: .init(
                callSites: extractCallSites(from: body, scope: scope.merging(parameters: params)),
                assignments: extractAssignments(from: body),
                fieldReads: fieldReadResolver.reads(in: body, scope: scope)
            )
        )
    }
}

// MARK: - Call sites

extension PythonExtractor {

    /// Matches Python `call { function: attribute { object, attribute } }`: `self.method(...)`,
    /// `self.prop.method(...)`, `receiver.method(...)`, and `TypeName.method(...)` (static call).
    func resolveCallSite(_ node: Node, scope: CallSiteScope) -> CallSite? {
        guard node.nodeType == "call", let funcNode = node.child(byFieldName: "function") else { return nil }

        // Bare call `name(...)`: no receiver type recorded, so the diagram layers resolve it to a
        // top-level function (or drop it, e.g. builtins/constructors).
        if funcNode.nodeType == "identifier" {
            return CallSite(receiver: .free, methodName: text(funcNode), location: loc(node))
        }

        guard funcNode.nodeType == "attribute",
              let attr = funcNode.child(byFieldName: "attribute"),
              let object = funcNode.child(byFieldName: "object") else { return nil }

        let methodName = text(attr)

        if object.nodeType == "identifier", text(object) == "self" {
            return CallSite(receiver: .selfDispatch, methodName: methodName, location: loc(node))
        }

        var receiverName: String?
        if object.nodeType == "identifier" {
            receiverName = text(object)
        } else if object.nodeType == "attribute",
                  let innerObject = object.child(byFieldName: "object"),
                  innerObject.nodeType == "identifier", text(innerObject) == "self",
                  let innerAttr = object.child(byFieldName: "attribute") {
            receiverName = text(innerAttr)
        }

        guard let name = receiverName else { return nil }
        return scope.resolvedCallSite(receiverName: name, methodName: methodName, location: loc(node))
    }

    /// Provable local-variable types: an explicit annotation, a `Foo()` construction of a declared
    /// type, or (Python requires an explicit receiver) a same-type call `x = self.compute()` with an
    /// unambiguous return type. `self.x = …` targets an `attribute` node, not `identifier`, so it's
    /// left to field synthesis.
    func localBindings(in body: Node, scope: CallSiteScope) -> [String: String] {
        collectLocalBindings(in: body) { node in
            guard node.nodeType == "assignment",
                  let left = node.child(byFieldName: "left"), left.nodeType == "identifier"
            else { return nil }
            let name = text(left)
            if let typeField = node.child(byFieldName: "type"),
               let typeId = typeField.firstChild(withType: "identifier") {
                return (name, text(typeId))
            }
            guard let right = node.child(byFieldName: "right"), right.nodeType == "call",
                  let function = right.child(byFieldName: "function")
            else { return nil }
            if function.nodeType == "identifier", declaredTypeNames.contains(text(function)) {
                return (name, text(function))
            }
            if function.nodeType == "attribute",
               let object = function.child(byFieldName: "object"), object.nodeType == "identifier",
               text(object) == "self",
               let attr = function.child(byFieldName: "attribute"),
               let returnType = scope.knownMethodReturnTypes[text(attr)] {
                return (name, returnType)
            }
            return nil
        }
    }
}

// MARK: - Assignment extraction

extension PythonExtractor: AssignmentResolving {

    func resolveAssignment(_ node: Node) -> VariableAssignment? {
        switch node.nodeType {
        case "assignment":
            return resolveAssignment(node, op: .assign)
        case "augmented_assignment":
            return resolveAssignment(node, op: .compound)
        default:
            return nil
        }
    }

    private func resolveAssignment(_ node: Node, op: VariableAssignment.Operator) -> VariableAssignment? {
        guard let left = node.child(byFieldName: "left"),
              let target = parseAssignmentTarget(text(left)),
              let right = node.child(byFieldName: "right") else { return nil }
        // Compound results depend on the previous value: record the whole statement as a
        // non-enumerable expression.
        let value: VariableAssignment.Value = op == .compound
            ? .init(kind: .expression, text: expressionSnippet(node))
            : classifyValue(right)
        return VariableAssignment(
            targetName: target.name,
            targetReceiver: target.receiver,
            op: op,
            value: value,
            location: loc(node)
        )
    }

    private static let literalNodeTypes = LiteralNodeTypes(
        boolean: ["true", "false"],
        numeric: ["integer", "float"],
        string: ["string", "concatenated_string"],
        nilLiteral: ["none"]
    )

    func classifyValue(_ node: Node) -> VariableAssignment.Value {
        if let literal = classifyLiteral(node, Self.literalNodeTypes) { return literal }
        let valueText = trimmedText(node)
        if let enumCase = enumCaseValue(fromAccessText: valueText) {
            return enumCase
        }
        return .init(kind: .expression, text: expressionSnippet(node))
    }
}

// MARK: - Field reads

extension PythonExtractor {
    /// Bare names and the `attribute` of a `self.<attr>` access are both `identifier` nodes.
    var fieldReadResolver: FieldReadResolver {
        FieldReadResolver(context: context, identifierTypes: ["identifier"])
    }
}
