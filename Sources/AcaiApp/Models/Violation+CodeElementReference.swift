import AcaiCore
import AcaiQuality

extension Violation {
    /// The code element this violation is about, so a Findings-style row can resolve through
    /// `CodeElementReference` like everything else. `nil` if `subject` is empty.
    ///
    /// `subject` carries no structured kind of its own (a type id, module name, or `A→B` edge) —
    /// rather than switch on `ruleKind` (a bare `String`, easy to drift out of sync with
    /// `QualityEvaluator`), this resolves structurally: split on "→" for an edge, else take the
    /// first comma-separated member and look it up against `artifact` to tell a type id from a
    /// module name.
    func codeElementReference(in artifact: CodeArtifact) -> CodeElementReference? {
        if let arrowRange = subject.range(of: "→") {
            let source = String(subject[..<arrowRange.lowerBound])
            let target = String(subject[arrowRange.upperBound...])
            guard !source.isEmpty, !target.isEmpty else { return nil }
            let kind = detail["kind"].flatMap(Relationship.Kind.init(rawValue:)) ?? .dependency
            return .relationship(source: source, target: target, kind: kind)
        }
        guard let first = subject.split(separator: ",").first.map(String.init), !first.isEmpty else { return nil }
        if artifact.flattened().contains(where: { $0.id == first }) {
            return .type(id: first)
        }
        return .module(name: first)
    }
}
