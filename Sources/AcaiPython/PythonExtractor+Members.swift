import AcaiCore
import AcaiTreeSitter

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
        fields.append(contentsOf: synthesizeSelfFields(fromMethods: methodNodes, existing: existing))

        let scope = CallSiteScope(
            knownProperties: propertyMap(from: fields),
            knownTypeNames: declaredTypeNames,
            // Python fields are frequently untyped (`self.x = …`), so the typed `propertyMap` misses
            // them — pass every field name so field-read capture (issue #111) sees them all.
            knownPropertyNames: Set(fields.map(\.name)),
            knownMethodReturnTypes: methodReturnTypeMap(fromMethodNodes: methodNodes)
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

    /// Built only from methods with an explicit `-> Type` (Python has no return-type inference to
    /// fall back to); ambiguous overloaded names are dropped rather than guessed.
    private func methodReturnTypeMap(
        fromMethodNodes methodNodes: [(node: Node, decorators: [String])]
    ) -> [String: String] {
        var typesByName: [String: Set<String>] = [:]
        for method in methodNodes {
            guard let nameNode = method.node.child(byFieldName: "name"),
                  let returnTypeNode = method.node.child(byFieldName: "return_type"),
                  let returnType = extractType(fromTypeField: returnTypeNode)
            else { continue }
            typesByName[text(nameNode), default: []].insert(returnType.name)
        }
        return typesByName.compactMapValues { $0.count == 1 ? $0.first : nil }
    }

    private func propertyMap(from fields: [Member]) -> [String: String] {
        var map: [String: String] = [:]
        for field in fields {
            if let typeName = field.type?.name { map[field.name] = typeName }
        }
        return map
    }

    // MARK: - Class-body fields

    private func collectClassBodyFields(_ body: Node, scope: CallSiteScope) -> [Member] {
        var fields: [Member] = []
        for child in body.namedChildren() where child.nodeType == "expression_statement" {
            for assign in child.namedChildren() where assign.nodeType == "assignment" {
                guard let left = assign.child(byFieldName: "left"), left.nodeType == "identifier" else { continue }
                let name = text(left)
                let type = assign.child(byFieldName: "type").flatMap { extractType(fromTypeField: $0) }
                let initial = assign.child(byFieldName: "right").map { classifyValue($0) }
                fields.append(Member(
                    name: name,
                    kind: .property,
                    accessLevel: accessLevel(forName: name),
                    type: type,
                    location: loc(assign),
                    callSites: extractCallSites(from: assign.child(byFieldName: "right"), scope: scope),
                    initialValue: initial,
                    referencedTypeNames: referencedTypeNames(in: assign.child(byFieldName: "right"))
                ))
            }
        }
        return fields
    }

    // MARK: - Instance-attribute synthesis (self.x = …)

    /// `self.x = …` inside methods is the only place idiomatic Python declares instance attributes,
    /// so this synthesises properties from those assignments, skipping ones already in `existing`.
    private func synthesizeSelfFields(
        fromMethods methods: [(node: Node, decorators: [String])], existing: Set<String>
    ) -> [Member] {
        var seen = existing
        var fields: [Member] = []
        for method in methods {
            guard let body = method.node.child(byFieldName: "body") else { continue }
            var assignmentNodes: [Node] = []
            collectAssignmentNodes(body, into: &assignmentNodes)
            for assign in assignmentNodes {
                guard let left = assign.child(byFieldName: "left"), left.nodeType == "attribute",
                      let object = left.child(byFieldName: "object"), object.nodeType == "identifier",
                      text(object) == "self",
                      let attr = left.child(byFieldName: "attribute") else { continue }
                let name = text(attr)
                guard !seen.contains(name) else { continue }
                seen.insert(name)
                let type = assign.child(byFieldName: "type").flatMap { extractType(fromTypeField: $0) }
                    ?? constructedType(fromAssignmentRight: assign.child(byFieldName: "right"))
                fields.append(Member(
                    name: name,
                    kind: .property,
                    accessLevel: accessLevel(forName: name),
                    type: type,
                    location: loc(assign)
                ))
            }
        }
        return fields
    }

    /// Mirrors the construction check `localBindings` already applies to locals: a direct `Foo()`
    /// construction of a same-file declared type (not `foo.Bar()`), when there's no type annotation.
    private func constructedType(fromAssignmentRight right: Node?) -> TypeReference? {
        guard let call = right, call.nodeType == "call",
              let function = call.child(byFieldName: "function"), function.nodeType == "identifier",
              declaredTypeNames.contains(text(function))
        else { return nil }
        return TypeReference(name: text(function))
    }

    private func collectAssignmentNodes(_ node: Node, into result: inout [Node]) {
        if node.nodeType == "assignment" || node.nodeType == "augmented_assignment" {
            result.append(node)
        }
        for child in node.namedChildren() {
            collectAssignmentNodes(child, into: &result)
        }
    }

    // MARK: - Methods & functions

    func extractCallable(_ node: Node, decorators: [String], scope: CallSiteScope) -> Member {
        let name = node.child(byFieldName: "name").map { text($0) } ?? "_anonymous"
        var params = node.child(byFieldName: "parameters").map { extractParameters($0) } ?? []
        if let first = params.first, first.internalName == "self" || first.internalName == "cls" {
            params.removeFirst()
        }
        let returnType = node.child(byFieldName: "return_type").flatMap { extractType(fromTypeField: $0) }

        let decoratorTails = Set(decorators.map { $0.components(separatedBy: ".").last ?? $0 })
        var kind: MemberKind = (name == "__init__") ? .initializer : .method
        var modifiers: [Modifier] = []
        var isComputed = false

        if decoratorTails.contains("property") || decoratorTails.contains("cached_property")
            || decoratorTails.contains("setter") || decoratorTails.contains("getter") {
            kind = .property
            isComputed = true
        }
        if decoratorTails.contains("staticmethod") { modifiers.append(.static) }
        if decoratorTails.contains("abstractmethod") { modifiers.append(.abstract) }
        if decoratorTails.contains("final") { modifiers.append(.final) }
        if hasDirectChildText("async", in: node) { modifiers.append(.async) }

        let body = node.child(byFieldName: "body")
        return Member(
            name: name,
            kind: kind,
            accessLevel: accessLevel(forName: name),
            modifiers: modifiers,
            type: returnType,
            parameters: params,
            isComputed: isComputed,
            annotations: decorators,
            location: loc(node),
            callSites: extractCallSites(from: body, scope: scope.merging(parameters: params)),
            assignments: extractAssignments(from: body),
            fieldReads: fieldReadResolver.reads(in: body, scope: scope),
            referencedTypeNames: referencedTypeNames(in: body),
            cyclomaticComplexity: cyclomaticComplexity(in: body, branchKinds: Self.branchNodeKinds)
        )
    }

    /// Short-circuit `and`/`or` are excluded so the metric stays consistent across languages
    /// (several grammars model them as generic binary nodes rather than decision points).
    static let branchNodeKinds: Set<String> = [
        "if_statement", "elif_clause", "for_statement", "while_statement", "except_clause",
        "case_clause"
    ]
}
