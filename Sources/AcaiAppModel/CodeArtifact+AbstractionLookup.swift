import AcaiCore

// MARK: - Abstraction Lookup (interface resolution)

extension CodeArtifact {
    public func abstractionType(named participantName: String) -> TypeDeclaration? {
        let canonical = participantName.canonicalTypeName
        guard let type = types.first(where: { $0.name == canonical }),
              type.kind == .protocol || type.kind == .interface else { return nil }
        return type
    }

    public func conformerNames(ofAbstractionNamed participantName: String) -> [String] {
        guard let abstraction = abstractionType(named: participantName) else { return [] }
        let conformerIDs = relationships
            .filter { $0.target == abstraction.id && ($0.kind == .conformance || $0.kind == .inheritance) }
            .map(\.source)
        var seen: Set<String> = []
        return conformerIDs
            .compactMap { id in types.first(where: { $0.id == id })?.name }
            .filter { seen.insert($0).inserted }
            .sorted()
    }
}

extension String {
    /// A participant name with an existential spelling (`any P`, `some P`) reduced to the bare type
    /// name the artifact declares.
    fileprivate var canonicalTypeName: String {
        for prefix in ["any ", "some "] where hasPrefix(prefix) {
            return String(dropFirst(prefix.count))
        }
        return self
    }
}
