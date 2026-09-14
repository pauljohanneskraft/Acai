import AcaiCore
import AcaiTreeSitter

// MARK: - PythonMemberExtractor

/// Shapes a `Member` value from an already-parsed method/field node plus its already-resolved pieces
/// (parameters, return type, call sites, assignments, field reads) — mirrors `AcaiSwift`'s
/// `MemberExtractor`: this never resolves a call site or reads `PythonExtractor`'s declaration state
/// itself, it only builds the value from what the caller already computed. Stateless beyond `context`.
struct PythonMemberExtractor {
    let context: SourceFileContext

    /// Short-circuit `and`/`or` are excluded so the metric stays consistent across languages
    /// (several grammars model them as generic binary nodes rather than decision points).
    static let branchNodeKinds: Set<String> = [
        "if_statement", "elif_clause", "for_statement", "while_statement", "except_clause",
        "case_clause"
    ]

    func callable(
        _ node: Node,
        decorators: [String],
        parameters: [Parameter],
        returnType: TypeReference?,
        accessLevel: AccessLevel,
        callSites: [CallSite],
        assignments: [VariableAssignment],
        fieldReads: [FieldAccess]
    ) -> Member {
        let name = node.child(byFieldName: "name").map { $0.text(in: context) } ?? "_anonymous"
        var params = parameters
        if let first = params.first, first.internalName == "self" || first.internalName == "cls" {
            params.removeFirst()
        }

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
        if node.hasDirectChildText("async", in: context) { modifiers.append(.async) }

        let body = node.child(byFieldName: "body")
        return Member(
            name: name,
            kind: kind,
            accessLevel: accessLevel,
            modifiers: modifiers,
            type: returnType,
            parameters: params,
            isComputed: isComputed,
            annotations: decorators,
            location: node.location(in: context),
            callSites: callSites,
            assignments: assignments,
            fieldReads: fieldReads,
            referencedTypeNames: body?.referencedTypeNames(in: context) ?? [],
            cyclomaticComplexity: body?.cyclomaticComplexity(branchKinds: Self.branchNodeKinds)
        )
    }

    func field(
        name: String,
        type: TypeReference?,
        accessLevel: AccessLevel,
        location: SourceLocation,
        callSites: [CallSite] = [],
        initialValue: VariableAssignment.Value? = nil,
        referencedTypeNames: [String] = []
    ) -> Member {
        Member(
            name: name,
            kind: .property,
            accessLevel: accessLevel,
            type: type,
            location: location,
            callSites: callSites,
            initialValue: initialValue,
            referencedTypeNames: referencedTypeNames
        )
    }

    /// Built only from methods with an explicit `-> Type` (Python has no return-type inference to
    /// fall back to); ambiguous overloaded names are dropped rather than guessed.
    func methodReturnTypeMap(fromMethodNodes methodNodes: [(node: Node, decorators: [String])]) -> [String: String] {
        let resolver = PythonTypeReferenceResolver(context: context)
        var typesByName: [String: Set<String>] = [:]
        for method in methodNodes {
            guard let nameNode = method.node.child(byFieldName: "name"),
                  let returnTypeNode = method.node.child(byFieldName: "return_type"),
                  let returnType = resolver.resolve(fromTypeField: returnTypeNode)
            else { continue }
            typesByName[nameNode.text(in: context), default: []].insert(returnType.name)
        }
        return typesByName.compactMapValues { $0.count == 1 ? $0.first : nil }
    }

    func propertyMap(from fields: [Member]) -> [String: String] {
        var map: [String: String] = [:]
        for field in fields {
            if let typeName = field.type?.name { map[field.name] = typeName }
        }
        return map
    }

    /// `self.x = …` inside methods is the only place idiomatic Python declares instance attributes,
    /// so this synthesises properties from those assignments, skipping ones already in `existing`.
    func synthesizeSelfFields(
        fromMethods methods: [(node: Node, decorators: [String])],
        existing: Set<String>,
        declaredTypeNames: Set<String>,
        accessLevel: (String) -> AccessLevel
    ) -> [Member] {
        let resolver = PythonTypeReferenceResolver(context: context)
        var seen = existing
        var fields: [Member] = []
        for method in methods {
            guard let body = method.node.child(byFieldName: "body") else { continue }
            var assignmentNodes: [Node] = []
            collectAssignmentNodes(body, into: &assignmentNodes)
            for assign in assignmentNodes {
                guard let left = assign.child(byFieldName: "left"), left.nodeType == "attribute",
                      let object = left.child(byFieldName: "object"), object.nodeType == "identifier",
                      object.text(in: context) == "self",
                      let attr = left.child(byFieldName: "attribute") else { continue }
                let name = attr.text(in: context)
                guard !seen.contains(name) else { continue }
                seen.insert(name)
                let type = assign.child(byFieldName: "type").flatMap { resolver.resolve(fromTypeField: $0) }
                    ?? constructedType(
                        fromAssignmentRight: assign.child(byFieldName: "right"), declaredTypeNames: declaredTypeNames
                    )
                fields.append(field(
                    name: name, type: type, accessLevel: accessLevel(name), location: assign.location(in: context)
                ))
            }
        }
        return fields
    }

    /// Mirrors the construction check call-site resolution already applies to locals: a direct
    /// `Foo()` construction of a same-file declared type (not `foo.Bar()`), when there's no type
    /// annotation.
    private func constructedType(fromAssignmentRight right: Node?, declaredTypeNames: Set<String>) -> TypeReference? {
        guard let call = right, call.nodeType == "call",
              let function = call.child(byFieldName: "function"), function.nodeType == "identifier",
              declaredTypeNames.contains(function.text(in: context))
        else { return nil }
        return TypeReference(name: function.text(in: context))
    }

    private func collectAssignmentNodes(_ node: Node, into result: inout [Node]) {
        if node.nodeType == "assignment" || node.nodeType == "augmented_assignment" {
            result.append(node)
        }
        for child in node.namedChildren() {
            collectAssignmentNodes(child, into: &result)
        }
    }
}

extension PythonExtractor {
    var memberExtractor: PythonMemberExtractor { PythonMemberExtractor(context: context) }
}
