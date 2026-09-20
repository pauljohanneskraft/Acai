import AcaiCore
import AcaiTreeSitter

/// Walks a Python file and builds its `CodeArtifact`.
///
/// Conforms to nothing: the declaration state lives in a ``DeclarationBuilder`` it owns, and every
/// shared algorithm reaches it as an injected collaborator — so the small types below
/// (`PythonMemberExtractor`, `PythonBaseClassResolver`, …) can be handed the same collaborators
/// instead of having to route through this type. Every one of them is built exactly once, here.
struct PythonExtractor {

    private let context: SourceFileContext
    private let typeReferenceResolver: PythonTypeReferenceResolver
    private let baseClassResolver: PythonBaseClassResolver
    private let parameterExtractor: PythonParameterExtractor
    private let memberExtractor: PythonMemberExtractor
    private let typeDeclarationExtractor: PythonTypeDeclarationExtractor
    private let assignmentSyntax: PythonAssignmentSyntax
    private let callSites: CallSiteResolver
    private let assignments: AssignmentResolver
    private let fieldReads: FieldReadResolver

    private var declarations = DeclarationBuilder()

    /// Bare top-level calls (`main()`, or the body of `if __name__ == "__main__":`) have no caller
    /// to attach to, so they are collected here and given a synthetic member in ``extract()``.
    private var topLevelCallSites: [CallSite] = []

    /// Takes the parsed tree so the declared-type pre-pass — which every call-site decision depends
    /// on — runs before the collaborators that read it are built, rather than leaving them to be
    /// assembled later or rebuilt per call.
    init(source: String, fileName: String, root: Node) {
        let context = SourceFileContext(source: source, fileName: fileName)
        let typeReferenceResolver = PythonTypeReferenceResolver(context: context)
        let baseClassResolver = PythonBaseClassResolver(context: context, typeReferences: typeReferenceResolver)
        let declaredTypeNames = TypeNamePrepass(declarationNodeTypes: ["class_definition"])
            .names(in: root) { $0.child(byFieldName: "name").map { $0.text(in: context) } }

        self.context = context
        self.typeReferenceResolver = typeReferenceResolver
        self.baseClassResolver = baseClassResolver
        parameterExtractor = PythonParameterExtractor(context: context, typeReferences: typeReferenceResolver)
        memberExtractor = PythonMemberExtractor(context: context, typeReferences: typeReferenceResolver)
        typeDeclarationExtractor = PythonTypeDeclarationExtractor(
            context: context, baseClassResolver: baseClassResolver
        )
        assignmentSyntax = PythonAssignmentSyntax(context: context)
        callSites = CallSiteResolver(
            syntax: PythonCallSiteSyntax(context: context, declaredTypeNames: declaredTypeNames)
        )
        assignments = AssignmentResolver(syntax: assignmentSyntax)
        // Bare names and the `attribute` of a `self.<attr>` access are both `identifier` nodes.
        fieldReads = FieldReadResolver(context: context, identifierTypes: ["identifier"])

        declarations.declaredTypeNames = declaredTypeNames
    }

    // MARK: - Entry point

    mutating func extract(from root: Node) -> CodeArtifact {
        for child in root.children() {
            visitTopLevel(child)
        }
        if !topLevelCallSites.isEmpty {
            declarations.freestandingFunctions.append(Member(
                name: "<top-level>", kind: .method, accessLevel: .public, callSites: topLevelCallSites))
        }
        declarations.resolveRelationshipNames()
        return declarations.artifact(language: .python, filePath: context.fileName)
    }
}

// MARK: - Top-level traversal

extension PythonExtractor {

    private mutating func visitTopLevel(_ node: Node) {
        switch node.nodeType {
        case "class_definition":
            declarations.types.append(extractClass(node, decorators: []))
        case "function_definition":
            declarations.freestandingFunctions.append(
                extractCallable(node, decorators: [], scope: moduleScope())
            )
        case "decorated_definition":
            visitDecorated(node)
        case "expression_statement":
            for assign in node.namedChildren() where assign.nodeType == "assignment" {
                if let member = extractModuleVariable(assign) {
                    declarations.globalVariables.append(member)
                }
            }
            topLevelCallSites.append(contentsOf: callSites.callSites(in: node, scope: moduleScope()))
        case "if_statement":
            // Covers the idiomatic `if __name__ == "__main__": main()` entry point.
            topLevelCallSites.append(contentsOf: callSites.callSites(in: node, scope: moduleScope()))
        default:
            break
        }
    }

    private mutating func visitDecorated(_ node: Node) {
        let decorators = extractDecorators(node)
        guard let def = node.child(byFieldName: "definition") else { return }
        switch def.nodeType {
        case "class_definition":
            declarations.types.append(extractClass(def, decorators: decorators))
        case "function_definition":
            declarations.freestandingFunctions.append(
                extractCallable(def, decorators: decorators, scope: moduleScope())
            )
        default:
            break
        }
    }

    private func moduleScope() -> CallSiteScope {
        CallSiteScope(knownTypeNames: declarations.declaredTypeNames)
    }

    private func extractModuleVariable(_ assign: Node) -> Member? {
        guard let left = assign.child(byFieldName: "left"), left.nodeType == "identifier" else { return nil }
        let name = left.text(in: context)
        let type = assign.child(byFieldName: "type").flatMap { typeReferenceResolver.resolve(fromTypeField: $0) }
        let initial = assign.child(byFieldName: "right").map { assignmentSyntax.classifyValue($0) }
        return Member(
            name: name,
            kind: .property,
            accessLevel: name.pythonAccessLevel,
            type: type,
            location: assign.location(in: context),
            initialValue: initial
        )
    }

    /// Bare decorator names, e.g. `@app.route(...)` → `"app.route"`, `@dataclass` → `"dataclass"`.
    private func extractDecorators(_ node: Node) -> [String] {
        var result: [String] = []
        for child in node.children() where child.nodeType == "decorator" {
            var raw = child.text(in: context)
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

    private mutating func extractClass(_ node: Node, decorators: [String]) -> TypeDeclaration {
        let name = node.child(byFieldName: "name").map { $0.text(in: context) } ?? "_Anonymous"
        // Namespaced so a nested `Inner` doesn't collide with a top-level `Inner`.
        let qualified = declarations.qualifiedName(name)
        let bases = baseClassResolver.bases(for: node, className: qualified)
        declarations.relationships.append(contentsOf: bases.relationships)

        var decl = typeDeclarationExtractor.declaration(
            for: node,
            signature: .init(
                name: name, qualifiedName: qualified, decorators: decorators, bases: bases,
                accessLevel: name.pythonAccessLevel
            )
        )

        if let body = node.child(byFieldName: "body") {
            let outer = declarations.enter(namespace: qualified)
            defer { declarations.leave(outer) }
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

    /// Class-body `NAME = value` assignments are enum cases here, not properties.
    private mutating func parseEnumBody(_ body: Node, into decl: inout TypeDeclaration) {
        let scope = CallSiteScope(knownTypeNames: declarations.declaredTypeNames)
        for child in body.namedChildren() {
            switch child.nodeType {
            case "expression_statement":
                for assign in child.namedChildren() where assign.nodeType == "assignment" {
                    guard let left = assign.child(byFieldName: "left"), left.nodeType == "identifier" else { continue }
                    let rawValue = assign.child(byFieldName: "right").map { $0.text(in: context) }
                    decl.enumCases.append(EnumCase(
                        name: left.text(in: context), rawValue: rawValue, location: assign.location(in: context)
                    ))
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

    private mutating func parseClassBody(_ body: Node, into decl: inout TypeDeclaration) {
        for child in body.namedChildren() {
            if child.nodeType == "class_definition" {
                decl.nestedTypes.append(extractClass(child, decorators: []))
            } else if child.nodeType == "decorated_definition",
                      let def = child.child(byFieldName: "definition"), def.nodeType == "class_definition" {
                decl.nestedTypes.append(extractClass(def, decorators: extractDecorators(child)))
            }
        }

        let methodNodes = collectMethodNodes(body)
        let declaredTypeNames = declarations.declaredTypeNames

        // A class-body initializer can't reference `self`, so file-level type names are the only
        // resolvable receivers.
        var fields = collectClassBodyFields(body, scope: CallSiteScope(knownTypeNames: declaredTypeNames))
        let existing = Set(fields.map(\.name))
        fields.append(contentsOf: memberExtractor.synthesizeSelfFields(
            fromMethods: methodNodes, existing: existing, declaredTypeNames: declaredTypeNames,
            accessLevel: \.pythonAccessLevel
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

    private func collectMethodNodes(_ body: Node) -> [(node: Node, decorators: [String])] {
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

    private func collectClassBodyFields(_ body: Node, scope: CallSiteScope) -> [Member] {
        var fields: [Member] = []
        for child in body.namedChildren() where child.nodeType == "expression_statement" {
            for assign in child.namedChildren() where assign.nodeType == "assignment" {
                guard let left = assign.child(byFieldName: "left"), left.nodeType == "identifier" else { continue }
                let name = left.text(in: context)
                let right = assign.child(byFieldName: "right")
                fields.append(memberExtractor.field(
                    name: name,
                    type: assign.child(byFieldName: "type")
                        .flatMap { typeReferenceResolver.resolve(fromTypeField: $0) },
                    accessLevel: name.pythonAccessLevel,
                    location: assign.location(in: context),
                    callSites: callSites.callSites(in: right, scope: scope),
                    initialValue: right.map { assignmentSyntax.classifyValue($0) },
                    referencedTypeNames: right?.referencedTypeNames(in: context) ?? []
                ))
            }
        }
        return fields
    }

    private func extractCallable(_ node: Node, decorators: [String], scope: CallSiteScope) -> Member {
        let params = node.child(byFieldName: "parameters").map { parameterExtractor.parameters($0) } ?? []
        let returnType = node.child(byFieldName: "return_type")
            .flatMap { typeReferenceResolver.resolve(fromTypeField: $0) }
        let name = node.child(byFieldName: "name").map { $0.text(in: context) } ?? "_anonymous"
        let body = node.child(byFieldName: "body")

        return memberExtractor.callable(
            node,
            signature: .init(
                decorators: decorators, parameters: params, returnType: returnType,
                accessLevel: name.pythonAccessLevel
            ),
            references: .init(
                callSites: callSites.callSites(in: body, scope: scope.merging(parameters: params)),
                assignments: assignments.assignments(in: body),
                fieldReads: fieldReads.reads(in: body, scope: scope)
            )
        )
    }
}
