import AcaiCore
import AcaiDiagram

extension DeadCodeScan.Candidate {
    /// A qualified `typeName` matching no simple type name leaves the member unqualified.
    func codeElementReference(in artifact: CodeArtifact) -> CodeElementReference? {
        guard let typeName, artifact.flattened().contains(where: { $0.name == typeName }) else {
            return .method(typeName: nil, methodName: memberName)
        }
        return .method(typeName: typeName, methodName: memberName)
    }
}
