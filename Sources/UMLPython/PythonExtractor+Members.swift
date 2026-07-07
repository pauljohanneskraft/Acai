import UMLCore
import UMLTreeSitter

// MARK: - Members (methods, fields, self.x synthesis)

extension PythonExtractor {

    /// Parses a (non-enum) class body: nested classes, methods, class-body fields, and instance
    /// attributes synthesised from `self.x = …` assignments inside the methods.
    mutating func parseClassBody(_ body: Node, into decl: inout TypeDeclaration) {
        // Nested classes.
        for child in body.namedChildren() {
            if child.nodeType == "class_definition" {
                decl.nestedTypes.append(extractClass(child, decorators: []))
            } else if child.nodeType == "decorated_definition",
                      let def = child.child(byFieldName: "definition"), def.nodeType == "class_definition" {
                decl.nestedTypes.append(extractClass(def, decorators: extractDecorators(child)))
            }
        }

        let methodNodes = collectMethodNodes(body)

        // Fields come from two places, both required for real Python code:
        // (a) class-body annotated/assigned attributes, (b) `self.x = …` inside methods.
        var fields = collectClassBodyFields(body)
        let existing = Set(fields.map(\.name))
        fields.append(contentsOf: synthesizeSelfFields(fromMethods: methodNodes, existing: existing))

        let scope = CallSiteScope(
            knownProperties: propertyMap(from: fields),
            knownTypeNames: declaredTypeNames,
            // Python fields are frequently untyped (`self.x = …`), so the typed `propertyMap` misses
            // them — pass every field name so field-read capture (issue #111) sees them all.
            knownPropertyNames: Set(fields.map(\.name))
        )

        decl.members.append(contentsOf: fields)
        for method in methodNodes {
            decl.members.append(extractCallable(method.node, decorators: method.decorators, scope: scope))
        }
    }

    /// Function definitions in a class body, paired with their decorator names (empty when bare).
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

    private func propertyMap(from fields: [Member]) -> [String: String] {
        var map: [String: String] = [:]
        for field in fields {
            if let typeName = field.type?.name { map[field.name] = typeName }
        }
        return map
    }

    // MARK: - Class-body fields

    /// Direct class-body attributes: plain `x = …`, annotated `x: T`, or annotated `x: T = …`
    /// (the dataclass/`__slots__`-free style of field declaration).
    private func collectClassBodyFields(_ body: Node) -> [Member] {
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
                    initialValue: initial,
                    referencedTypeNames: referencedTypeNames(in: assign.child(byFieldName: "right"))
                ))
            }
        }
        return fields
    }

    // MARK: - Instance-attribute synthesis (self.x = …)

    /// Synthesises property members from `self.x = …` assignments inside method bodies. This is the
    /// only place idiomatic Python declares instance attributes, so it is core to producing useful
    /// diagrams. Attributes already declared in the class body (passed via `existing`) are skipped,
    /// and each attribute is emitted once even if assigned in several methods. A type is recorded
    /// only when the assignment is annotated (`self.x: T = …`).
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

    /// Collects every `assignment`/`augmented_assignment` node reachable from `node`, in source order.
    private func collectAssignmentNodes(_ node: Node, into result: inout [Node]) {
        if node.nodeType == "assignment" || node.nodeType == "augmented_assignment" {
            result.append(node)
        }
        for child in node.namedChildren() {
            collectAssignmentNodes(child, into: &result)
        }
    }

    // MARK: - Methods & functions

    /// Extracts a `function_definition` as a `Member` (works for methods and module-level functions).
    /// `self`/`cls` is dropped from the parameter list; `__init__` becomes an initializer; decorators
    /// drive kind/modifiers (`@property` → computed, `@staticmethod` → static, `@abstractmethod`
    /// → abstract, `@final` → final).
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
            callSites: extractCallSites(from: body, scope: scope),
            assignments: extractAssignments(from: body),
            fieldReads: fieldReadResolver.reads(in: body, scope: scope),
            referencedTypeNames: referencedTypeNames(in: body),
            cyclomaticComplexity: cyclomaticComplexity(in: body, branchKinds: Self.branchNodeKinds)
        )
    }

    /// Python structural decision-point node types for cyclomatic complexity: conditionals, loops,
    /// exception handlers, `match` cases and ternaries. Short-circuit `and`/`or` are excluded so the
    /// metric is consistent across languages (several grammars model them as generic binary nodes).
    static let branchNodeKinds: Set<String> = [
        "if_statement", "elif_clause", "for_statement", "while_statement", "except_clause",
        "case_clause"
    ]
}
