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
    /// Lowercased method names that are framework/runtime entry points regardless of any caller
    /// (e.g. `main`, a Flutter `build`).
    public var methodNames: Set<String>

    public init(annotations: Set<String> = [], methodNames: Set<String> = []) {
        self.annotations = annotations
        self.methodNames = methodNames
    }

    /// Whether `member` is marked as an entry point by one of this language's annotation or
    /// name markers. Annotation markers are compared by their normalized `annotationName`.
    public func marks(_ member: Member) -> Bool {
        if methodNames.contains(member.name.lowercased()) { return true }
        return member.annotations.contains { annotations.contains($0.annotationName) }
    }
}
