import AcaiCore

/// Captures statically-observable reads of a type's own stored properties from a tree-sitter body
/// (cohesion/feature-envy accuracy).
///
/// Deliberately best-effort and grammar-light: it records every identifier-like node whose text
/// matches a known stored-property name as a bare/`self`-qualified read. No scope tracking — a local
/// shadowing a property is recorded under the same name; consumers filter by name and tolerate that
/// ambiguity, as they do for [VariableAssignment](/documentation/acaicore/variableassignment).
public struct FieldReadResolver {
    private let context: SourceFileContext
    private let identifierTypes: Set<String>

    /// - Parameter context: the file being parsed, used to read node text and source locations.
    /// - Parameter identifierTypes: the grammar's node types that denote a readable identifier or
    ///   member name (e.g. `"identifier"`, `"property_identifier"`, `"simple_identifier"`).
    ///   Over-inclusion is harmless — the text is filtered against the known-property set.
    public init(context: SourceFileContext, identifierTypes: Set<String>) {
        self.context = context
        self.identifierTypes = identifierTypes
    }

    public func reads(in body: Node?, scope: CallSiteScope) -> [FieldAccess] {
        reads(in: body, knownProperties: scope.knownPropertyNames)
    }

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
