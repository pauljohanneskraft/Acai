import AcaiCore
import AcaiDiagram

extension DeadCodeScan.Candidate {
    /// The declaration this candidate points at, from the type and member names it carries. A
    /// `typeName` naming no type in `artifact` — a qualified id for a type that two modules declare
    /// under the same simple name — leaves the member unqualified rather than inventing a type.
    func codeElementReference(in artifact: CodeArtifact) -> CodeElementReference? {
        guard let typeName, artifact.flattened().contains(where: { $0.name == typeName }) else {
            return .method(typeName: nil, methodName: memberName)
        }
        return .method(typeName: typeName, methodName: memberName)
    }
}
