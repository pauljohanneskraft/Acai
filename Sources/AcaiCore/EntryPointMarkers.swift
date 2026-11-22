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
    /// Lowercased method names that are framework/runtime entry points regardless of the type they
    /// are declared on (`main`, a pytest hook). Reserve this for conventions a framework matches by
    /// name; a member a framework protocol *requires* belongs in `conformanceMembers`, so an
    /// unrelated type's same-named method is still reported.
    public var methodNames: Set<String>
    /// Supertype name → the lowercased member names that supertype requires of its subtypes. A
    /// member matches only when its own type inherits from or conforms to that supertype, so
    /// SwiftUI's `body` exempts a `View`'s and not an unrelated type's. Keyed on the name the
    /// source writes, which is how a protocol declared outside the analysed sources arrives.
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

    /// Whether `member` is marked as an entry point by one of this language's markers: a normalized
    /// annotation, a name-based marker, or a `conformanceMembers` entry for one of `supertypes` —
    /// the transitive supertype names of the type declaring `member`.
    public func marks(_ member: Member, inheritingFrom supertypes: Set<String>) -> Bool {
        let name = member.name.lowercased()
        if methodNames.contains(name) { return true }
        if member.annotations.contains(where: { annotations.contains($0.annotationName) }) { return true }
        return supertypes.contains { conformanceMembers[$0]?.contains(name) ?? false }
    }
}
