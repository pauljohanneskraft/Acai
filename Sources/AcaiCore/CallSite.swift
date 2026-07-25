/// Where a ``CallSite`` is dispatched — the statically-determined receiver of a call.
///
/// Replaces the older `receiverType: String?`, whose `nil` conflated a call on the enclosing
/// instance with a free-function call.
public enum CallReceiver: Codable, Equatable, Hashable, Sendable {

    /// A call on the enclosing instance (`self.foo()` / `this.foo()`).
    case selfDispatch

    /// A call whose receiver resolves to a declared type.
    ///
    /// **Producer contract:** the associated value must be a **simple** type name matching a declared
    /// ``TypeDeclaration/name`` (not a qualified id) — sequence-diagram and call-graph resolution look
    /// the receiver up by simple name, so a qualified value silently drops the call.
    case type(String)

    /// A free-function call — no receiver.
    case free

    /// The receiver can't be resolved (a generic parameter / protocol existential with unknown concrete
    /// type). Counts toward neither `self` nor a declared type.
    case unknown

    /// A capitalised-identifier receiver not known to be a declared type within the file it was parsed
    /// in — possibly declared elsewhere in the project. ``CodeArtifact/resolvingCallSiteReceivers()``
    /// promotes it to ``type(_:)`` post-merge when exactly one declared type shares this simple name;
    /// until then, treat it the same as `unknown`.
    case unresolvedTypeName(String)

    /// A property-access chain (`a.b.c()`) whose head resolves to a known type (`headTypeName`) but
    /// whose intermediate `hops` (property names) couldn't be resolved within the file.
    /// ``CodeArtifact/resolvingCallSiteReceivers()`` walks each hop's declared property type through
    /// the full project post-merge; an unresolvable hop leaves this case in place.
    case propertyChain(headTypeName: String, hops: [String])

    /// A bare, lowercase receiver (`aProperty.method()`, or a chain off one) not resolvable within the
    /// file — typically because the enclosing type is split across multiple `extension` blocks and
    /// `aProperty` is declared in a sibling block this file never sees. `propertyName` is the
    /// unresolved receiver; `remainingHops` are further property accesses before the call. Resolved
    /// post-merge the same way as `propertyChain`, against the call site's own enclosing type.
    case ownProperty(propertyName: String, remainingHops: [String])

    /// A closure's implicit `$0`, bound to the *element* type of a same-type array-typed stored
    /// property not resolvable within the file (`addedRelationships.map { $0.reportPhrase() }` when
    /// `addedRelationships` lives in a sibling `extension` block). Unlike `ownProperty`, resolves to
    /// the property's *element* type; `propertyName` must name an array-typed property.
    case ownPropertyElement(propertyName: String)

    /// A local/guard-let binding from a same-type method call whose return type isn't resolvable
    /// within the file — typically because the method is declared in a sibling `extension` block.
    /// `methodName` is the method whose return type this defers to; `remainingHops` mirrors
    /// `ownProperty`. Resolved post-merge against the call site's own enclosing type.
    case ownMethodReturn(methodName: String, remainingHops: [String])
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

    /// The receiver's declared simple type name, or `nil` for a `self`/free/unresolved dispatch.
    public var receiverType: String? {
        if case .type(let name) = receiver { return name }
        return nil
    }
}
