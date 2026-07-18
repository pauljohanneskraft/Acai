import AcaiCore

// MARK: - Abstraction Lookup (interface resolution)
//
// Sequence-diagram participants are named after *declared receiver types*, which for Swift
// existentials include the `any ` / `some ` prefix (e.g. `any BuildSystemDetector`). These
// lookups canonicalize such names back to the underlying protocol/interface declaration so the
// config sheet can offer concrete-type mappings — while `typeMapping` keys stay the raw
// participant name, because the generator substitutes declared receiver strings verbatim.

extension CodeArtifact {

    /// The protocol/interface declaration behind a participant name, accepting existential
    /// spellings (`any P`, `some P`) as well as the plain name. `nil` when the name doesn't
    /// resolve to an abstraction.
    func abstractionType(named participantName: String) -> TypeDeclaration? {
        let canonical = Self.canonicalTypeName(participantName)
        guard let type = types.first(where: { $0.name == canonical }),
              type.kind == .protocol || type.kind == .interface else { return nil }
        return type
    }

    /// Names of concrete types that conform to / inherit from the named abstraction, found via
    /// relationship edges (relationships are id-based after enrichment). Sorted, de-duplicated.
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

    /// Strips Swift existential/opaque markers from a declared type name.
    private static func canonicalTypeName(_ name: String) -> String {
        for prefix in ["any ", "some "] where name.hasPrefix(prefix) {
            return String(name.dropFirst(prefix.count))
        }
        return name
    }
}
