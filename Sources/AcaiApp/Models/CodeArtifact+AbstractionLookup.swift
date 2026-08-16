import AcaiCore

// MARK: - Abstraction Lookup (interface resolution)

extension CodeArtifact {
    func abstractionType(named participantName: String) -> TypeDeclaration? {
        let canonical = Self.canonicalTypeName(participantName)
        guard let type = types.first(where: { $0.name == canonical }),
              type.kind == .protocol || type.kind == .interface else { return nil }
        return type
    }

    func conformerNames(ofAbstractionNamed participantName: String) -> [String] {
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

    private static func canonicalTypeName(_ name: String) -> String {
        for prefix in ["any ", "some "] where name.hasPrefix(prefix) {
            return String(name.dropFirst(prefix.count))
        }
        return name
    }
}
