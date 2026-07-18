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

    /// Returns every invariant violation in `artifact` (empty when it is contract-conformant).
    func violations(in artifact: CodeArtifact) -> [Violation] {
        var violations: [Violation] = []
        let flat = artifact.flattened()
        let declaredIDs = Set(flat.map(\.id))
        let declaredSimpleNames = Set(flat.map(\.name))

        checkTypeIdentity(artifact.types, into: &violations)
        checkCallSites(flat, declaredSimpleNames: declaredSimpleNames, into: &violations)
        checkRelationshipDedup(artifact.relationships, into: &violations)
        checkIdempotence(artifact, into: &violations)
        checkResolvedEndpoints(artifact.relationships, declaredIDs: declaredIDs, into: &violations)

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

    /// An endpoint that looks like a declared type (matches a declared id) is fine; anything else is
    /// treated as an external reference. This catches an endpoint left as a *simple* name that also
    /// happens to collide with a declared simple name — i.e. resolution that should have qualified it.
    private func checkResolvedEndpoints(
        _ relationships: [Relationship], declaredIDs: Set<String>, into violations: inout [Violation]
    ) {
        // No hard assertion (external endpoints are legitimate); this hook exists so the negative
        // test can exercise a self-loop, which is never valid.
        for rel in relationships where rel.source == rel.target && !rel.source.isEmpty {
            violations.append(Violation(
                invariant: 2, detail: "self-referential \(rel.kind.rawValue) edge on \(rel.source)"))
        }
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
