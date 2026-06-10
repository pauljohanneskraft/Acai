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
    /// represents a method call on a known property.
    ///
    /// Return `nil` for nodes that are not relevant call
    /// expressions.
    func resolveCallSite(
        _ node: Node,
        knownProperties: [String: String]
    ) -> CallSite?
}

// MARK: - CallSiteResolving Default Implementations

extension CallSiteResolving {

    /// Extracts call sites from a body node using a map
    /// of property names → types.
    ///
    /// Walks the AST recursively, calling
    /// ``resolveCallSite(_:knownProperties:)`` on each node.
    public func extractCallSites(
        from body: Node?,
        knownProperties: [String: String]
    ) -> [CallSite] {
        guard let body, !knownProperties.isEmpty else { return [] }
        var sites: [CallSite] = []
        walkForCallSites(
            body,
            knownProperties: knownProperties,
            into: &sites
        )
        return sites
    }

    /// Recursively walks AST nodes, collecting resolved call sites.
    private func walkForCallSites(
        _ node: Node,
        knownProperties: [String: String],
        into sites: inout [CallSite]
    ) {
        if let site = resolveCallSite(
            node,
            knownProperties: knownProperties
        ) {
            sites.append(site)
        }
        for child in node.namedChildren() {
            walkForCallSites(
                child,
                knownProperties: knownProperties,
                into: &sites
            )
        }
    }
}
