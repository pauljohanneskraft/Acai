import Foundation
import AcaiCore

// MARK: - TreeSitterExtracting

/// Protocol for tree-sitter-based language extractors.
///
/// Every language extractor (Kotlin, Java, JS/TS, Dart) conforms to this
/// protocol and **must** implement ``walkSourceFile(_:)`` — the compiler
/// enforces this at build time, so there is no risk of accidentally
/// inheriting a no-op default.
///
/// The protocol extension provides:
/// - **Convenience helpers** – `text(_:)`, `loc(_:)`, `qualifiedName(_:)`.
/// - **Artifact assembly** – `buildArtifact(language:)`.
/// - **Relationship resolution** – `resolveRelationshipNames()`.
/// - **Property-map builder** – `buildPropertyMap(from:)`.
public protocol TreeSitterExtracting {

    // MARK: - Required State

    /// The source-file context (source text + file name).
    var context: SourceFileContext { get }

    /// Accumulated type declarations discovered during extraction.
    var types: [TypeDeclaration] { get set }

    /// Simple names of every type declared in the file, collected in one pre-pass over the
    /// AST before bodies are extracted (so call-site resolution sees the *complete* set —
    /// including the enclosing type, nested types, and forward-declared siblings — rather
    /// than only types appended so far). Populate via ``collectDeclaredTypeNames(from:declarationNodeTypes:name:)``.
    var declaredTypeNames: Set<String> { get set }

    /// Accumulated inter-type relationships discovered during extraction.
    var relationships: [Relationship] { get set }

    /// Top-level functions that are not members of any type.
    var freestandingFunctions: [Member] { get set }

    /// The current namespace / package / library scope
    /// (used by ``qualifiedName(_:)``).
    var currentNamespace: String? { get set }

    // MARK: - Required Methods

    /// Walks the root AST node to extract top-level declarations.
    ///
    /// Each language module **must** implement this with its own
    /// AST traversal logic.
    mutating func walkSourceFile(_ node: Node)
}

// MARK: - TreeSitterExtracting Default Implementations

extension TreeSitterExtracting {

    // MARK: Convenience Helpers

    /// The source text covered by the given AST node.
    public func text(_ node: Node) -> String {
        let nsStr = context.source as NSString
        let nsRange = node.range
        guard nsRange.location != NSNotFound,
              nsRange.location + nsRange.length <= nsStr.length
        else { return "" }
        return nsStr.substring(with: nsRange)
    }

    /// The source location of the given AST node's start position.
    public func loc(_ node: Node) -> SourceLocation {
        let point = node.pointRange.lowerBound
        return SourceLocation(
            filePath: context.fileName,
            line: Int(point.row) + 1,
            column: Int(point.column) + 1
        )
    }

    /// Builds a fully-qualified name from ``currentNamespace``
    /// and a simple type name.
    public func qualifiedName(_ name: String) -> String {
        currentNamespace.map { "\($0).\(name)" } ?? name
    }

    /// Whether the node has an anonymous (keyword) child with the
    /// given text.
    public func hasAnonymousKeyword(
        _ keyword: String,
        in node: Node
    ) -> Bool {
        node.hasAnonymousChild(keyword, in: context)
    }

    /// Whether any direct child's text equals the given string.
    public func hasDirectChildText(
        _ value: String,
        in node: Node
    ) -> Bool {
        node.hasDirectChildText(value, in: context)
    }

    // MARK: Artifact Assembly

    /// Assembles the accumulated state into a ``AcaiCore/CodeArtifact``.
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

    /// Normalises an annotation/decorator's source text to the canonical `@Name` form, adding a
    /// leading `@` when the grammar's token omits it. (For grammars that instead include the `@`
    /// and want it stripped, do that at the call site — this only ever adds one.)
    public func normalizedAnnotation(_ text: String) -> String {
        text.hasPrefix("@") ? text : "@\(text)"
    }

    // MARK: Supertype Relationships

    /// Records an inheritance/conformance edge from `owner` (a type's id or qualified name) to each
    /// of `supertypes`, in order. Deduplicates the per-language "loop the supertypes and append a
    /// `Relationship`" step; the caller keeps ownership of its `inheritedTypes` list. The edges'
    /// `target` is each supertype's simple name — `resolveRelationshipNames()` later maps it to a
    /// qualified id.
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

    /// Resolves relationship source / target strings against
    /// the types already collected in ``types``.
    ///
    /// During extraction, supertype names are taken verbatim from
    /// source text (e.g. `Animal`), while type IDs are fully
    /// qualified (e.g. `com.example.Animal`). This post-processing
    /// step maps short names to qualified IDs so that relationships
    /// are immediately matchable without downstream resolution.
    public mutating func resolveRelationshipNames() {
        // Delegates to the single identity authority (`TypeIdentityResolver`) so per-file resolution
        // here uses the same name→id mapping and ambiguity rule as the agnostic enrichment pass.
        let resolver = TypeIdentityResolver(types: types)

        relationships = relationships.map { rel in
            var resolved = rel
            resolved.source = resolver.canonicalName(for: rel.source)
            resolved.target = resolver.canonicalName(for: rel.target)
            return resolved
        }

        // Also resolve inherited-type names so the codebase detail
        // view shows consistent naming (qualified IDs where possible).
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

    /// Builds a `[propertyName: typeName]` map from
    /// already-extracted members.
    ///
    /// Useful as input to call-site extraction.
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

    /// Builds a `[methodName: returnTypeName]` map from already-extracted members (unambiguous
    /// overloads only), so a same-type method call can seed a local's type the same way a direct
    /// construction already does (RC-I). Only usable by extractors that collect a type's full member
    /// set *before* resolving any body (CFamily, Dart) — one that resolves bodies inline as members
    /// are encountered needs its own per-type raw-syntax pre-pass instead, since a forward-declared
    /// method wouldn't yet be in `members` here.
    public func methodReturnTypeMap(from members: [Member]) -> [String: String] {
        var typesByName: [String: Set<String>] = [:]
        for member in members where member.kind == .method {
            if let typeName = member.type?.name {
                typesByName[member.name, default: []].insert(typeName)
            }
        }
        return typesByName.compactMapValues { $0.count == 1 ? $0.first : nil }
    }

    /// One pre-pass over the raw AST collecting the simple name of every type declaration
    /// (recursively, including nested types), so the full set is known before any body is
    /// resolved. `name` extracts the declaration node's simple name (declarations whose name
    /// can't be read — e.g. anonymous extensions — are skipped).
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

    /// Type-like identifier names referenced anywhere inside a member's body/initializer subtree —
    /// the construction/body dependencies the coupling metrics consume (e.g. `Foo()` constructions,
    /// `Foo.bar` static access, type annotations). Walks **iteratively** (an explicit stack, not
    /// recursion) so a deeply nested body can't overflow the stack. Over-captures every identifier
    /// token by design; the engine keeps only names that resolve to a known type, so noise is dropped.
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
    /// tree-sitter type is in `branchKinds` (the grammar's `if`/`for`/`while`/`case`/`catch`/`&&`/`||`/
    /// ternary node types — supplied by the language plugin, so this helper names no language). Returns
    /// `nil` when there is no body, so an aggregate metric distinguishes "not measured" from "no
    /// branches". Walks iteratively so a deeply nested body can't overflow the stack.
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

    /// Collects concrete parse problems from a best-effort tree: `ERROR` nodes (the parser
    /// could not make sense of the input) and `missing` nodes (a required token the source
    /// omitted, inserted during recovery). Walks *all* children, not just named ones, since
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
