/// A reference to a type at a *use* site: a member's value/return type, a supertype, or a generic
/// argument. Identity is the bare ``name`` — the engine has no resolved pointer here, only a string.
///
/// **Producer contract:** ``name`` must be the **simple** type name (`List`, not
/// `kotlin.collections.List`). Primitive/collection classification (which drives composition-vs-
/// aggregation edges and multiplicity) does *exact* name matching, so a qualified name here silently
/// produces wrong edges. See ``CodeArtifact`` enrichment.
public struct TypeReference: Codable, Equatable, Hashable, Sendable {
    /// The referenced type's **simple** (unqualified) name. Used verbatim for primitive/collection
    /// classification and for resolving the reference to a declared type.
    public var name: String
    /// Type arguments, recursively (`Dictionary<String, Foo>` → `[String, Foo]`). Only the top-level
    /// ``name`` is classified; arguments carry their own references.
    public var genericArguments: [TypeReference]
    /// Whether the reference is optional/nullable (`Foo?`) — surfaces as `0..1` multiplicity.
    public var isOptional: Bool
    /// Whether the reference is an array/collection of ``name`` (`[Foo]`) — surfaces as `*` multiplicity.
    public var isArray: Bool

    public init(
        name: String,
        genericArguments: [TypeReference] = [],
        isOptional: Bool = false,
        isArray: Bool = false
    ) {
        self.name = name
        self.genericArguments = genericArguments
        self.isOptional = isOptional
        self.isArray = isArray
    }
}
