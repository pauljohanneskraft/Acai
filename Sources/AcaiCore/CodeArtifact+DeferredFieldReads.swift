extension CodeArtifact {
    /// Promotes each member's ``Member/deferredFieldReads`` that name a property of its merged type
    /// into ``Member/fieldReads``, and drops the rest. Runs after extension resolution. Idempotent.
    public func resolvingDeferredFieldReads() -> CodeArtifact {
        var copy = self
        copy.types = types.map { $0.resolvingDeferredFieldReads() }
        copy.freestandingFunctions = freestandingFunctions.map { $0.promotingDeferredFieldReads(among: []) }
        return copy
    }
}

extension TypeDeclaration {
    func resolvingDeferredFieldReads() -> TypeDeclaration {
        var copy = self
        let properties = Set(members.filter { $0.kind == .property }.map(\.name))
        copy.members = members.map { $0.promotingDeferredFieldReads(among: properties) }
        copy.nestedTypes = nestedTypes.map { $0.resolvingDeferredFieldReads() }
        return copy
    }
}

extension Member {
    func promotingDeferredFieldReads(among properties: Set<String>) -> Member {
        guard let deferred = deferredFieldReads else { return self }
        var copy = self
        copy.fieldReads += deferred.filter { properties.contains($0.name) }
        copy.deferredFieldReads = nil
        return copy
    }
}
