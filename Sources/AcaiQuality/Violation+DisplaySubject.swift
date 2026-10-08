import AcaiCore

extension Violation {
    /// ``subject`` with each type id in it (a single id, an `A→B` edge or a `A,B,C` cycle) named by `names`.
    public func displaySubject(_ names: TypeDisplayNames) -> String {
        subject
            .components(separatedBy: "→")
            .map { edgeEnd in
                edgeEnd.components(separatedBy: ",").map(names.name(forID:)).joined(separator: ",")
            }
            .joined(separator: "→")
    }
}
