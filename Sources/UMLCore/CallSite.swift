/// Where a ``CallSite`` is dispatched — the statically-determined receiver of a call.
///
/// Replaces the older `receiverType: String?`, whose `nil` conflated a call on the enclosing
/// instance with a free-function call. Distinguishing them lets cohesion/feature-envy analyses
/// stop guessing that "no receiver ⇒ `self`" (issue #111).
public enum CallReceiver: Codable, Equatable, Hashable, Sendable {

    /// A call on the enclosing instance (`self.foo()` / `this.foo()`).
    case selfDispatch

    /// A call whose receiver resolves to a declared type.
    ///
    /// **Producer contract:** the associated value must be a **simple** type name matching a declared
    /// ``TypeDeclaration/name`` (not a qualified id). Sequence-diagram and call-graph resolution look
    /// the receiver up by simple name, so a qualified value silently drops the call. Enforced by the
    /// parser-conformance suite (issue #89, invariant 4).
    case type(String)

    /// A free-function call — no receiver.
    case free

    /// The call is observed but its receiver can't be resolved (a generic parameter / protocol
    /// existential whose concrete type is unknown). Counts toward neither `self` nor a declared type.
    case unknown

    /// A capitalised-identifier receiver not known to be a declared type *within the file it was
    /// parsed in* — possibly declared elsewhere in the project. Resolved post-merge by
    /// ``CodeArtifact/resolvingCallSiteReceivers()``, which promotes it to ``type(_:)`` when the
    /// merged project has exactly one declared type with this simple name; a consumer that runs
    /// before that pass (or receives an artifact it never ran on) treats this the same as `unknown` —
    /// never guesses across an ambiguous or absent match.
    case unresolvedTypeName(String)

    /// A call reached through a property-access chain (`a.b.c()`) whose head resolves to a known type
    /// (`headTypeName` — the enclosing type for a `self`-headed chain, or a known property's type) but
    /// whose intermediate hops (`hops`, each a property name) couldn't be resolved within the file.
    /// Resolved post-merge by ``CodeArtifact/resolvingCallSiteReceivers()``, which walks each hop's
    /// declared property type through the full project type graph; an unresolvable hop leaves this
    /// case in place, treated the same as `unknown` by any consumer.
    case propertyChain(headTypeName: String, hops: [String])

    /// A call reached through a bare, lowercase receiver (`aProperty.method()`, or a chain off one,
    /// `aProperty.b.method()`) that isn't resolvable within the file it was parsed in — typically
    /// because the enclosing type is split across multiple `extension` blocks (this project's own
    /// convention: `Type.swift` + `Type+Feature.swift`) and `aProperty` is declared in a sibling
    /// block this file never sees. `propertyName` is the unresolved receiver itself; `remainingHops`
    /// are any further property accesses before the method call. Resolved post-merge by
    /// ``CodeArtifact/resolvingCallSiteReceivers()``, which looks `propertyName` up against the call
    /// site's own (fully-merged) enclosing type, then walks `remainingHops` the same way
    /// `propertyChain` walks `hops`; an unresolvable property or hop leaves this case in place,
    /// treated the same as `unknown` by any consumer.
    case ownProperty(propertyName: String, remainingHops: [String])
}

/// A statically-observable call to a method or free function, recorded
/// inside a `Member`'s body during source analysis.
///
/// Parsers populate `Member.callSites` when they can determine the call target
/// from the source text. Dynamic dispatch (e.g. protocol witness calls through an
/// existential, closures stored in variables) may not be captured.
public struct CallSite: Codable, Equatable, Hashable, Sendable {

    /// How the call is dispatched — `self`, a declared type, a free function, or unresolved.
    public var receiver: CallReceiver

    /// The name of the method or function being called.
    public var methodName: String

    /// Source location of the call expression.
    public var location: SourceLocation?

    public init(
        receiver: CallReceiver,
        methodName: String,
        location: SourceLocation? = nil
    ) {
        self.receiver = receiver
        self.methodName = methodName
        self.location = location
    }

    /// The receiver's declared simple type name, or `nil` when the call is a `self`/free/unresolved
    /// dispatch. A convenience for the many consumers that only need the type-name lookup key.
    public var receiverType: String? {
        if case .type(let name) = receiver { return name }
        return nil
    }
}
