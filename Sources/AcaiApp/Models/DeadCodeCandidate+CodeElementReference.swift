import AcaiCore
import AcaiDiagram

extension DeadCodeScan.Candidate {
    /// The code element this candidate is about, so a Findings-style row can resolve through
    /// `CodeElementReference` like everything else — mirrors `Violation.codeElementReference(in:)`'s
    /// structural approach.
    ///
    /// `id` is `"TypeName.methodName"` for a type's member, or a bare function name for a
    /// freestanding function (`DeadCodeScan.report`'s construction) — resolved structurally by
    /// splitting on the last `.` and checking whether the prefix names a real type in `artifact`,
    /// since the candidate carries no structured kind of its own.
    func codeElementReference(in artifact: CodeArtifact) -> CodeElementReference? {
        guard let dotRange = id.range(of: ".", options: .backwards) else {
            return .method(typeName: nil, methodName: id)
        }
        let typeName = String(id[..<dotRange.lowerBound])
        let methodName = String(id[dotRange.upperBound...])
        guard !typeName.isEmpty, !methodName.isEmpty,
              artifact.flattened().contains(where: { $0.name == typeName })
        else {
            return .method(typeName: nil, methodName: id)
        }
        return .method(typeName: typeName, methodName: methodName)
    }
}
