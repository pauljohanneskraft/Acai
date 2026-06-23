import Foundation
import UMLCore

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

    /// Assembles the accumulated state into a ``UMLCore/CodeArtifact``.
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
        var nameToId: [String: String] = [:]

        func register(_ types: [TypeDeclaration]) {
            for type in types {
                nameToId[type.name] = type.id
                nameToId[type.qualifiedName] = type.id
                if let simple = type.name
                    .components(separatedBy: ".").last,
                   nameToId[simple] == nil {
                    nameToId[simple] = type.id
                }
                register(type.nestedTypes)
            }
        }
        register(types)

        relationships = relationships.map { rel in
            var resolved = rel
            if let id = nameToId[rel.source] {
                resolved.source = id
            }
            if let id = nameToId[rel.target] {
                resolved.target = id
            }
            return resolved
        }

        // Also resolve inherited-type names so the codebase detail
        // view shows consistent naming (qualified IDs where possible).
        func resolveInheritedTypes(
            in types: inout [TypeDeclaration]
        ) {
            for index in types.indices {
                for refIndex in types[index].inheritedTypes.indices {
                    let name = types[index].inheritedTypes[refIndex].name
                    if let id = nameToId[name] {
                        types[index].inheritedTypes[refIndex].name = id
                    }
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

// MARK: - CallSiteScope

/// The statically-known context used to resolve a method call's receiver to a type.
///
/// Resolution stays deliberately conservative — a call site is only captured when its
/// receiver is *provably* a known type: a typed stored property, an explicit `this`/`self`
/// (a call on the enclosing instance), or a `TypeName.method()` where `TypeName` is a
/// declared type. Anything else (locals, parameters, external/stdlib receivers) is dropped
/// so the resulting sequence diagrams keep their near-zero-false-edge guarantee.
public struct CallSiteScope: Sendable {
    /// `propertyName: typeName` for the enclosing type's stored properties.
    public var knownProperties: [String: String]
    /// Simple names of types declared in the current file (for `TypeName.method()`).
    public var knownTypeNames: Set<String>

    public init(
        knownProperties: [String: String] = [:],
        knownTypeNames: Set<String> = []
    ) {
        self.knownProperties = knownProperties
        self.knownTypeNames = knownTypeNames
    }

    /// Resolves a single-identifier receiver (`receiver.method()`) to a ``UMLCore/CallSite``:
    /// a typed stored property resolves to its declared type; otherwise a name matching a
    /// known type is treated as a static/`TypeName.method()` call. Returns `nil` for anything
    /// not provably resolvable (locals, parameters, external receivers).
    public func resolvedCallSite(
        receiverName: String,
        methodName: String,
        location: SourceLocation?
    ) -> CallSite? {
        if let receiverType = knownProperties[receiverName] {
            return CallSite(receiverType: receiverType, methodName: methodName, location: location)
        }
        if knownTypeNames.contains(receiverName) {
            return CallSite(receiverType: receiverName, methodName: methodName, location: location)
        }
        return nil
    }
}

// MARK: - CallSiteResolving

/// Opt-in protocol for extractors that support call-site resolution.
///
/// Not every language needs call-site extraction (e.g. Dart does not).
/// This protocol adds the capability by requiring a single method
/// ``resolveCallSite(_:knownProperties:)`` and providing the recursive
/// walk infrastructure in the extension.
public protocol CallSiteResolving: TreeSitterExtracting {

    /// Resolves a single AST node to a ``UMLCore/CallSite`` if it
    /// represents a statically-resolvable method call (on a known property,
    /// on `this`/`self`, or on a known type).
    ///
    /// Return `nil` for nodes that are not relevant call
    /// expressions, or whose receiver cannot be provably resolved.
    func resolveCallSite(
        _ node: Node,
        scope: CallSiteScope
    ) -> CallSite?
}

// MARK: - CallSiteResolving Default Implementations

extension CallSiteResolving {

    /// Extracts call sites from a body node using the statically-known ``CallSiteScope``.
    ///
    /// Walks the AST recursively, calling ``resolveCallSite(_:scope:)`` on each node.
    /// Unlike property-only resolution, this is worth walking even when no properties are
    /// known, because `this`/`self` and `TypeName.method()` calls are still resolvable.
    public func extractCallSites(
        from body: Node?,
        scope: CallSiteScope
    ) -> [CallSite] {
        guard let body else { return [] }
        var sites: [CallSite] = []
        walkForCallSites(body, scope: scope, into: &sites)
        return sites
    }

    /// Recursively walks AST nodes, collecting resolved call sites.
    private func walkForCallSites(
        _ node: Node,
        scope: CallSiteScope,
        into sites: inout [CallSite]
    ) {
        if let site = resolveCallSite(node, scope: scope) {
            sites.append(site)
        }
        for child in node.namedChildren() {
            walkForCallSites(child, scope: scope, into: &sites)
        }
    }

    /// Resolves a member call's `receiver` to a ``UMLCore/CallSite`` using the receiver decision tree
    /// shared by field-name-based grammars: `this.method()` → an unqualified self-call;
    /// `receiver.method()` and `this.prop.method()` → resolved against `scope`. The grammar-specific
    /// call-node unwrapping (finding the receiver node and method name) stays with the caller.
    public func resolveMemberCall(
        receiver: Node,
        methodName: String,
        grammar: MemberCallGrammar,
        scope: CallSiteScope,
        location: SourceLocation?
    ) -> CallSite? {
        // Pattern: this.method(args) — a direct call on the enclosing instance.
        if receiver.nodeType == grammar.selfNodeType {
            return CallSite(receiverType: nil, methodName: methodName, location: location)
        }

        var receiverName: String?
        if receiver.nodeType == "identifier" {
            receiverName = text(receiver)
        } else if receiver.nodeType == grammar.memberAccessType,
                  receiver.child(byFieldName: "object")?.nodeType == grammar.selfNodeType,
                  let member = receiver.child(byFieldName: grammar.memberField) {
            // Pattern: this.prop.method(args)
            receiverName = text(member)
        }

        guard let name = receiverName else { return nil }
        return scope.resolvedCallSite(receiverName: name, methodName: methodName, location: location)
    }
}

/// The grammar node types a language uses for member-call receiver resolution (see
/// ``CallSiteResolving/resolveMemberCall(receiver:methodName:grammar:scope:location:)``).
public struct MemberCallGrammar: Sendable {
    /// The node type of a `this`/`self` expression (e.g. `"this"`).
    public let selfNodeType: String
    /// The node type of a `<self>.<member>` access (e.g. `"field_access"`).
    public let memberAccessType: String
    /// The field name holding the member in that access (e.g. `"field"`).
    public let memberField: String

    public init(selfNodeType: String, memberAccessType: String, memberField: String) {
        self.selfNodeType = selfNodeType
        self.memberAccessType = memberAccessType
        self.memberField = memberField
    }
}
