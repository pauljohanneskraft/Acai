import Foundation
import AcaiCore

// MARK: - TreeSitterExtracting

/// The monolithic extractor shape: one type owning a file's whole declaration state and reaching
/// every shared algorithm by conforming.
///
/// Superseded — every member below forwards to a value that owns the algorithm and can be held by
/// anything (``DeclarationBuilder``, ``MemberIndex``, ``CallSiteResolver``, ``AssignmentResolver``,
/// ``TypeNamePrepass``, ``ParseDiagnosticsCollector``). A migrated plugin holds those directly and
/// does not conform to this at all; see `AcaiPython`. Deleted with the last conformer.
public protocol TreeSitterExtracting {

    // MARK: - Required State

    var context: SourceFileContext { get }

    var types: [TypeDeclaration] { get set }

    /// Collected in one pre-pass before bodies are extracted so call-site resolution sees the
    /// complete set, including forward-declared siblings. Populate via
    /// ``collectDeclaredTypeNames(from:declarationNodeTypes:name:)``.
    var declaredTypeNames: Set<String> { get set }

    var relationships: [Relationship] { get set }

    var freestandingFunctions: [Member] { get set }

    /// Top-level (module-scope) `let`/`var`/`val` declarations.
    var globalVariables: [Member] { get set }

    var currentNamespace: String? { get set }

    // MARK: - Required Methods

    mutating func walkSourceFile(_ node: Node)
}

// MARK: - TreeSitterExtracting Default Implementations

extension TreeSitterExtracting {

    // MARK: Convenience Helpers

    public func text(_ node: Node) -> String {
        node.text(in: context)
    }

    public func loc(_ node: Node) -> SourceLocation {
        node.location(in: context)
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
        declarationBuilder.artifact(language: language, filePath: context.fileName)
    }

    /// Adds a leading `@` when the grammar's token omits it; grammars that instead include the `@`
    /// and want it stripped should do that at the call site — this only ever adds one.
    public func normalizedAnnotation(_ text: String) -> String {
        text.hasPrefix("@") ? text : "@\(text)"
    }

    // MARK: Supertype Relationships

    /// The edges' `target` is each supertype's simple name; ``resolveRelationshipNames()`` later
    /// maps it to a qualified id.
    public mutating func recordSupertypeRelationships(
        from owner: String,
        to supertypes: [TypeReference],
        kind: Relationship.Kind
    ) {
        // Direct rather than through `DeclarationBuilder`: this runs once per declared type, and
        // round-tripping the arrays through a temporary builder would copy them each time.
        relationships.append(contentsOf: supertypes.map { $0.relationship(kind: kind, source: owner) })
    }

    // MARK: Relationship Resolution

    /// Supertype names are taken verbatim from source text (e.g. `Animal`) while type IDs are fully
    /// qualified (e.g. `com.example.Animal`); this maps short names to qualified IDs.
    public mutating func resolveRelationshipNames() {
        var builder = declarationBuilder
        builder.resolveRelationshipNames()
        relationships = builder.relationships
        types = builder.types
    }

    /// A migrated plugin stores the builder instead of rebuilding one per call.
    private var declarationBuilder: DeclarationBuilder {
        var builder = DeclarationBuilder()
        builder.types = types
        builder.relationships = relationships
        builder.freestandingFunctions = freestandingFunctions
        builder.globalVariables = globalVariables
        builder.declaredTypeNames = declaredTypeNames
        return builder
    }

    // MARK: Property Map

    public func buildPropertyMap(
        from members: [Member]
    ) -> [String: String] {
        MemberIndex(members: members).propertyTypes
    }

    /// Unambiguous overloads only, so a same-type method call can seed a local's type like a direct
    /// construction does. Only usable by extractors that collect a type's full member set before
    /// resolving any body (CFamily, Dart) — one that resolves bodies inline needs its own per-type
    /// pre-pass instead, since a forward-declared method wouldn't yet be in `members` here.
    public func methodReturnTypeMap(from members: [Member]) -> [String: String] {
        MemberIndex(members: members).methodReturnTypes
    }

    /// Declarations whose name can't be read via `name` are skipped.
    public func collectDeclaredTypeNames(
        from root: Node,
        declarationNodeTypes: Set<String>,
        name: (Node) -> String?
    ) -> Set<String> {
        TypeNamePrepass(declarationNodeTypes: declarationNodeTypes).names(in: root, name: name)
    }

    /// Over-captures every identifier by design; the engine keeps only names that resolve to a
    /// known type.
    public func referencedTypeNames(in body: Node?) -> [String] {
        body?.referencedTypeNames(in: context) ?? []
    }

    /// The cyclomatic complexity of a method `body` (see `Node.cyclomaticComplexity(branchKinds:)`).
    /// Returns `nil` when there's no body, distinguishing "not measured" from "no branches".
    public func cyclomaticComplexity(in body: Node?, branchKinds: Set<String>) -> Int? {
        body?.cyclomaticComplexity(branchKinds: branchKinds)
    }

    /// Collects concrete parse problems from a best-effort tree. Call only when `root.hasError`.
    public func collectParseDiagnostics(from root: Node) -> [ParseDiagnostic] {
        ParseDiagnosticsCollector(context: context).diagnostics(in: root)
    }
}
