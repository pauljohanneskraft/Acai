import UMLCore

/// Captures statically-observable reads of a type's own stored properties from a tree-sitter body
/// (issue #111 — cohesion/feature-envy accuracy). A value you configure with the grammar's
/// identifier node types and ask for ``reads(in:knownProperties:)`` — not a protocol mixed into the
/// extractor, so the walk lives on the value that owns it.
///
/// Deliberately best-effort and grammar-light: it records every identifier-like node whose text
/// matches a known stored-property name as a bare/`self`-qualified read (`receiver` nil). No scope
/// tracking — a local shadowing a property, or a `foo.prop` member whose name collides with one of
/// the type's own properties, is recorded under the same name; consumers filter by name and tolerate
/// that ambiguity, exactly as they do for ``UMLCore/VariableAssignment``.
public struct FieldReadResolver {
    private let context: SourceFileContext
    private let identifierTypes: Set<String>

    /// - Parameters:
    ///   - context: the source-file context used to read node text and locations.
    ///   - identifierTypes: the grammar's node types that denote a readable identifier or member name
    ///     (e.g. `"identifier"`, `"property_identifier"`, `"simple_identifier"`). Over-inclusion is
    ///     harmless — the text is filtered against the known-property set.
    public init(context: SourceFileContext, identifierTypes: Set<String>) {
        self.context = context
        self.identifierTypes = identifierTypes
    }

    /// Field reads in `body`, filtered to the enclosing type's stored properties (from `scope`).
    public func reads(in body: Node?, scope: CallSiteScope) -> [FieldAccess] {
        reads(in: body, knownProperties: scope.knownPropertyNames)
    }

    /// Field reads in `body`, in source (pre-order) order, filtered to `knownProperties`.
    public func reads(in body: Node?, knownProperties: Set<String>) -> [FieldAccess] {
        guard let body, !knownProperties.isEmpty else { return [] }
        var reads: [FieldAccess] = []
        collect(from: body, knownProperties: knownProperties, into: &reads)
        return reads
    }

    private func collect(
        from node: Node, knownProperties: Set<String>, into reads: inout [FieldAccess]
    ) {
        if let nodeType = node.nodeType, identifierTypes.contains(nodeType) {
            let name = node.text(in: context)
            if knownProperties.contains(name) {
                reads.append(FieldAccess(name: name, receiver: nil, location: node.location(in: context)))
            }
        }
        for child in node.namedChildren() {
            collect(from: child, knownProperties: knownProperties, into: &reads)
        }
    }
}
