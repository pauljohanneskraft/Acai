/// Language-supplied description of what makes a member *reachable by contract* even when no call
/// site targets it — so dead-code analysis doesn't flag framework/test entry points as unused. This
/// is language data (a JUnit `@Test`, a Flutter `build`, an Android lifecycle callback), injected via
/// `LanguageConfiguration`; the agnostic engine reads it and names no language.
///
/// The universal rules (public API is reachable from outside, an `override` satisfies a supertype
/// contract, a protocol/interface member is a requirement) are handled by the analyzer itself — this
/// carries only the parts that differ per language/framework.
public struct EntryPointMarkers: Sendable, Equatable, Hashable, Codable {
    /// Normalized annotation markers (`@Test` → `test`) that make a member an entry point: test
    /// entry points, framework-lifecycle callbacks, DI-invoked methods.
    public var annotations: Set<String>
    /// Lowercased names a framework finds by convention on any type (`main`, a pytest hook).
    public var methodNames: Set<String>
    /// Supertype name as the source writes it → the lowercased members it requires of its subtypes.
    public var conformanceMembers: [String: Set<String>]

    public init(
        annotations: Set<String> = [],
        methodNames: Set<String> = [],
        conformanceMembers: [String: Set<String>] = [:]
    ) {
        self.annotations = annotations
        self.methodNames = methodNames
        self.conformanceMembers = conformanceMembers
    }

    /// `supertypes` are the transitive supertype names of the type declaring `member`.
    public func marks(_ member: Member, inheritingFrom supertypes: Set<String>) -> Bool {
        let name = member.name.lowercased()
        if methodNames.contains(name) { return true }
        if member.annotations.contains(where: { annotations.contains($0.annotationName) }) { return true }
        return supertypes.contains { conformanceMembers[$0]?.contains(name) ?? false }
    }
}
