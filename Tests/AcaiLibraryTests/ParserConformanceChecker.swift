import Foundation
import AcaiLibrary

/// Checks the implicit producer-contract invariants (issue #89) that every `CodeParser` must satisfy
/// for enrichment and rendering to work. Operates on an already-`enriched()` `CodeArtifact`, so it
/// runs against any parser + fixture pair (and against hand-built artifacts, for negative tests).
///
/// Each invariant is documented on the producing API (`CodeParser`, `TypeDeclaration`, `Relationship`,
/// `TypeReference`, `CallSite`); this makes those docs executable — a naive new plugin fails here at
/// test time instead of silently rendering an empty diagram.
struct ParserConformanceChecker {
    /// A single contract violation, tagged with the invariant number from issue #89.
    struct Violation: CustomStringConvertible {
        let invariant: Int
        let detail: String
        var description: String { "[#\(invariant)] \(detail)" }
    }

    func violations(in artifact: CodeArtifact) -> [Violation] {
        var violations: [Violation] = []
        let flat = artifact.flattened()
        let declaredIDs = Set(flat.map(\.id))
        let declaredSimpleNames = Set(flat.map(\.name))

        checkTypeIdentity(artifact.types, into: &violations)
        checkCallSites(flat, declaredSimpleNames: declaredSimpleNames, into: &violations)
        checkTypeReferenceNames(artifact.types, into: &violations)
        checkRelationshipDedup(artifact.relationships, into: &violations)
        checkIdempotence(artifact, into: &violations)
        checkResolvedEndpoints(
            artifact.relationships, supertypesOf: flat, declaredIDs: declaredIDs,
            resolver: TypeIdentityResolver(types: artifact.types), into: &violations)

        return violations
    }

    // MARK: - Invariant 1: id == qualifiedName; name is simple

    private func checkTypeIdentity(_ types: [TypeDeclaration], into violations: inout [Violation]) {
        for type in types {
            if type.id != type.qualifiedName {
                violations.append(Violation(
                    invariant: 1,
                    detail: "type '\(type.name)': id (\(type.id)) != qualifiedName (\(type.qualifiedName))"))
            }
            let simple = type.qualifiedName.components(separatedBy: ".").last ?? type.qualifiedName
            if type.name != simple {
                violations.append(Violation(
                    invariant: 1,
                    detail: "type id \(type.id): name '\(type.name)' is not the simple tail of "
                        + "qualifiedName '\(type.qualifiedName)'"))
            }
            // Invariant 12: nested-type ids/qualified names are hierarchically prefixed by the parent.
            for nested in type.nestedTypes where nested.kind != .extension {
                if !nested.qualifiedName.hasPrefix(type.qualifiedName + ".") {
                    violations.append(Violation(
                        invariant: 12,
                        detail: "nested type '\(nested.qualifiedName)' is not prefixed by parent "
                            + "'\(type.qualifiedName).'"))
                }
            }
            checkTypeIdentity(type.nestedTypes, into: &violations)
        }
    }

    // MARK: - Invariant 4: a CallReceiver.type carries a simple name matching a declared type

    private func checkCallSites(
        _ flat: [TypeDeclaration], declaredSimpleNames: Set<String>, into violations: inout [Violation]
    ) {
        for type in flat {
            for member in type.members {
                for site in member.callSites {
                    // Only `.type` carries a name; `.selfDispatch`/`.free`/`.unknown` structurally can't.
                    guard let receiver = site.receiverType else { continue }
                    if receiver.contains(".") {
                        violations.append(Violation(
                            invariant: 4,
                            detail: "call site in \(type.id).\(member.name): receiver type "
                                + "'\(receiver)' is not a simple name"))
                    }
                }
            }
        }
    }

    // MARK: - Invariant 4: TypeReference.name carries a simple name

    /// `inheritedTypes` is deliberately excluded: enrichment (``CodeArtifact/enriched(using:)``)
    /// rewrites its entries to the canonical (qualified) id of the resolved supertype, which is the
    /// documented exception to the simple-name contract on ``TypeDeclaration/inheritedTypes``.
    private func checkTypeReferenceNames(_ types: [TypeDeclaration], into violations: inout [Violation]) {
        for type in types {
            for reference in typeReferences(in: type) {
                checkSimpleName(reference, ownerID: type.id, into: &violations)
            }
            checkTypeReferenceNames(type.nestedTypes, into: &violations)
        }
    }

    private func typeReferences(in type: TypeDeclaration) -> [TypeReference] {
        var references = (type.genericParameters + type.associatedTypes).flatMap { $0.constraints.map(\.type) }
        for member in type.members {
            references += member.type.map { [$0] } ?? []
            references += member.parameters.compactMap(\.type)
            references += member.genericParameters.flatMap { $0.constraints.map(\.type) }
        }
        return references
    }

    private func checkSimpleName(_ reference: TypeReference, ownerID: String, into violations: inout [Violation]) {
        if reference.name.contains(".") {
            violations.append(Violation(
                invariant: 4,
                detail: "type '\(ownerID)': TypeReference name '\(reference.name)' is not a simple name"))
        }
        for argument in reference.genericArguments {
            checkSimpleName(argument, ownerID: ownerID, into: &violations)
        }
    }

    // MARK: - Invariant 13: relationships are deduplicated by (source, target, kind)

    private func checkRelationshipDedup(_ relationships: [Relationship], into violations: inout [Violation]) {
        var seen = Set<String>()
        for rel in relationships {
            let key = "\(rel.source)→\(rel.target):\(rel.kind.rawValue)"
            if !seen.insert(key).inserted {
                violations.append(Violation(
                    invariant: 13, detail: "duplicate relationship \(key) survived enrichment"))
            }
        }
    }

    // MARK: - Invariant 2/7: resolved endpoints reference real declared ids

    /// The contract says a relationship or supertype endpoint is *either* a name the resolver maps to
    /// a declared id *or* a legitimately-external name. So an endpoint that `TypeIdentityResolver`
    /// still resolves to a declared id it does not already equal is a violation: enrichment left a
    /// name behind where the canonical id was available, and the diagram renders a duplicate node
    /// beside the real type. `.external` (nothing declared under that name) and `.ambiguous`
    /// (deliberately left unresolved, and separately diagnosed) both pass.
    private func checkResolvedEndpoints(
        _ relationships: [Relationship], supertypesOf types: [TypeDeclaration], declaredIDs: Set<String>,
        resolver: TypeIdentityResolver, into violations: inout [Violation]
    ) {
        for rel in relationships {
            for (endpoint, role) in [(rel.source, "source"), (rel.target, "target")] {
                if endpoint.isEmpty {
                    violations.append(Violation(
                        invariant: 2, detail: "\(rel.kind.rawValue) edge has an empty \(role)"))
                    continue
                }
                appendUnresolvedEndpoint(
                    endpoint, declaredIDs: declaredIDs, resolver: resolver,
                    describedAs: "\(role) of a \(rel.kind.rawValue) edge to "
                        + "'\(role == "source" ? rel.target : rel.source)'",
                    into: &violations)
            }
            if rel.source == rel.target && !rel.source.isEmpty {
                violations.append(Violation(
                    invariant: 2, detail: "self-referential \(rel.kind.rawValue) edge on \(rel.source)"))
            }
        }

        for type in types {
            for supertype in type.inheritedTypes {
                appendUnresolvedEndpoint(
                    supertype.name, declaredIDs: declaredIDs, resolver: resolver,
                    describedAs: "supertype of '\(type.id)'", into: &violations)
            }
        }
    }

    private func appendUnresolvedEndpoint(
        _ endpoint: String, declaredIDs: Set<String>, resolver: TypeIdentityResolver,
        describedAs description: String, into violations: inout [Violation]
    ) {
        guard !declaredIDs.contains(endpoint), let resolved = resolver.resolvedID(for: endpoint) else {
            return
        }
        violations.append(Violation(
            invariant: 2,
            detail: "\(description) is '\(endpoint)', which is not a declared id but resolves to "
                + "'\(resolved.value)' — enrichment should have canonicalised it"))
    }

    // MARK: - Enrichment idempotence

    private func checkIdempotence(_ artifact: CodeArtifact, into violations: inout [Violation]) {
        let reEnriched = artifact.enriched(using: artifact.standardLanguageResolver)
        if Set(reEnriched.relationships.map { "\($0.source)→\($0.target):\($0.kind.rawValue)" })
            != Set(artifact.relationships.map { "\($0.source)→\($0.target):\($0.kind.rawValue)" }) {
            violations.append(Violation(
                invariant: 7, detail: "enrichment is not idempotent: re-running changed the edge set"))
        }
    }
}
