import Foundation
import AcaiCore

// MARK: - TreeSitterExtracting

public protocol TreeSitterExtracting {

    // MARK: - Required State

    var context: SourceFileContext { get }

    var types: [TypeDeclaration] { get set }

    /// Collected in one pre-pass before bodies are extracted so call-site resolution sees the complete
    /// set, including forward-declared siblings. Populate via
    /// ``collectDeclaredTypeNames(from:declarationNodeTypes:name:)``.
    var declaredTypeNames: Set<String> { get set }

    var relationships: [Relationship] { get set }

    var freestandingFunctions: [Member] { get set }

    var currentNamespace: String? { get set }

    // MARK: - Required Methods

    mutating func walkSourceFile(_ node: Node)
}

// MARK: - TreeSitterExtracting Default Implementations

extension TreeSitterExtracting {

    // MARK: Convenience Helpers

    public func text(_ node: Node) -> String {
        let nsStr = context.source as NSString
        let nsRange = node.range
        guard nsRange.location != NSNotFound,
              nsRange.location + nsRange.length <= nsStr.length
        else { return "" }
        return nsStr.substring(with: nsRange)
    }

    public func loc(_ node: Node) -> SourceLocation {
        let point = node.pointRange.lowerBound
        return SourceLocation(
            filePath: context.fileName,
            line: Int(point.row) + 1,
            column: Int(point.column) + 1
        )
    }

    public func qualifiedName(_ name: String) -> String {
        currentNamespace.map { "\($0).\(name)" } ?? name
    }

    public func hasAnonymousKeyword(
        _ keyword: String,
        in node: Node
    ) -> Bool {
        node.hasAnonymousChild(keyword, in: context)
    }

    public func hasDirectChildText(
        _ value: String,
        in node: Node
    ) -> Bool {
        node.hasDirectChildText(value, in: context)
    }

    // MARK: Artifact Assembly

    public func buildArtifact(
        language: CodeArtifact.SourceLanguage
    ) -> CodeArtifact {
        CodeArtifact(
            metadata: .init(
                sourceLanguage: language,
                filePaths: [context.fileName]
            ),
            types: types,
            relationships: relationships,
            freestandingFunctions: freestandingFunctions
        )
    }

    /// Adds a leading `@` when the grammar's token omits it; grammars that instead include the `@`
    /// and want it stripped should do that at the call site — this only ever adds one.
    public func normalizedAnnotation(_ text: String) -> String {
        text.hasPrefix("@") ? text : "@\(text)"
    }

    // MARK: Supertype Relationships

    /// The edges' `target` is each supertype's simple name; `resolveRelationshipNames()` later maps it
    /// to a qualified id.
    public mutating func recordSupertypeRelationships(
        from owner: String,
        to supertypes: [TypeReference],
        kind: Relationship.Kind
    ) {
        for supertype in supertypes {
            relationships.append(Relationship(kind: kind, source: owner, target: supertype.name))
        }
    }

    // MARK: Relationship Resolution

    /// Supertype names are taken verbatim from source text (e.g. `Animal`) while type IDs are fully
    /// qualified (e.g. `com.example.Animal`); this maps short names to qualified IDs.
    public mutating func resolveRelationshipNames() {
        // Delegates to `TypeIdentityResolver` so per-file resolution uses the same name→id mapping
        // and ambiguity rule as the agnostic enrichment pass.
        let resolver = TypeIdentityResolver(types: types)

        relationships = relationships.map { rel in
            var resolved = rel
            resolved.source = resolver.canonicalName(for: rel.source)
            resolved.target = resolver.canonicalName(for: rel.target)
            return resolved
        }

        // Also resolve inherited-type names for consistent naming in the codebase detail view.
        func resolveInheritedTypes(in types: inout [TypeDeclaration]) {
            for index in types.indices {
                for refIndex in types[index].inheritedTypes.indices {
                    let name = types[index].inheritedTypes[refIndex].name
                    types[index].inheritedTypes[refIndex].name = resolver.canonicalName(for: name)
                }
                resolveInheritedTypes(in: &types[index].nestedTypes)
            }
        }
        resolveInheritedTypes(in: &types)
    }

    // MARK: Property Map

    public func buildPropertyMap(
        from members: [Member]
    ) -> [String: String] {
        var map: [String: String] = [:]
        for member in members where member.kind == .property {
            if let typeName = member.type?.name {
                map[member.name] = typeName
            }
        }
        return map
    }

    /// Unambiguous overloads only, so a same-type method call can seed a local's type like a direct
    /// construction does. Only usable by extractors that collect a type's full member set before
    /// resolving any body (CFamily, Dart) — one that resolves bodies inline needs its own per-type
    /// pre-pass instead, since a forward-declared method wouldn't yet be in `members` here.
    public func methodReturnTypeMap(from members: [Member]) -> [String: String] {
        var typesByName: [String: Set<String>] = [:]
        for member in members where member.kind == .method {
            if let typeName = member.type?.name {
                typesByName[member.name, default: []].insert(typeName)
            }
        }
        return typesByName.compactMapValues { $0.count == 1 ? $0.first : nil }
    }

    /// Declarations whose name can't be read via `name` are skipped.
    public func collectDeclaredTypeNames(
        from root: Node,
        declarationNodeTypes: Set<String>,
        name: (Node) -> String?
    ) -> Set<String> {
        var names: Set<String> = []
        func walk(_ node: Node) {
            if let type = node.nodeType, declarationNodeTypes.contains(type), let typeName = name(node) {
                names.insert(typeName)
            }
            for index in 0..<node.childCount {
                node.child(at: index).map(walk)
            }
        }
        walk(root)
        return names
    }

    /// Walks iteratively (explicit stack) so a deeply nested body can't overflow the stack.
    /// Over-captures every identifier by design; the engine keeps only names that resolve to a known
    /// type.
    public func referencedTypeNames(in body: Node?) -> [String] {
        guard let body else { return [] }
        var names: Set<String> = []
        var stack: [Node] = [body]
        while let node = stack.popLast() {
            if node.nodeType?.hasSuffix("identifier") == true {
                names.insert(text(node))
            }
            for index in 0..<node.childCount {
                node.child(at: index).map { stack.append($0) }
            }
        }
        return Array(names)
    }

    /// The cyclomatic complexity of a method `body`: `1 +` the count of decision-point nodes whose
    /// tree-sitter type is in `branchKinds` (supplied by the language plugin, so this helper names no
    /// language). Returns `nil` when there's no body, distinguishing "not measured" from "no branches".
    public func cyclomaticComplexity(in body: Node?, branchKinds: Set<String>) -> Int? {
        guard let body else { return nil }
        var complexity = 1
        var stack: [Node] = [body]
        while let node = stack.popLast() {
            if let type = node.nodeType, branchKinds.contains(type) {
                complexity += 1
            }
            for index in 0..<node.childCount {
                node.child(at: index).map { stack.append($0) }
            }
        }
        return complexity
    }

    /// Collects concrete parse problems from a best-effort tree: `ERROR` nodes and `missing` nodes
    /// (a required token the source omitted). Walks all children, not just named ones, since
    /// error/missing nodes are frequently unnamed. Call only when `root.hasError`.
    public func collectParseDiagnostics(from root: Node) -> [ParseDiagnostic] {
        var diagnostics: [ParseDiagnostic] = []
        func walk(_ node: Node) {
            if node.isMissing {
                diagnostics.append(ParseDiagnostic(
                    location: loc(node), kind: .missing,
                    message: "missing \(node.nodeType ?? "token")"
                ))
            } else if node.nodeType == "ERROR" {
                diagnostics.append(ParseDiagnostic(
                    location: loc(node), kind: .error, message: "unexpected syntax"
                ))
            }
            for index in 0..<node.childCount {
                node.child(at: index).map(walk)
            }
        }
        walk(root)
        return diagnostics
    }
}
