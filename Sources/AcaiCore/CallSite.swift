public enum CallReceiver: Codable, Equatable, Hashable, Sendable {

    case selfDispatch

    /// A call whose receiver resolves to a declared type.
    ///
    /// **Producer contract:** the associated value must be a **simple** type name matching a declared
    /// ``TypeDeclaration/name`` (not a qualified id) — sequence-diagram and call-graph resolution look
    /// the receiver up by simple name, so a qualified value silently drops the call.
    case type(String)

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

/// Dynamic dispatch (e.g. protocol witness calls through an existential, closures stored in
/// variables) may not be captured — parsers only populate this from statically-observable source text.
public struct CallSite: Codable, Equatable, Hashable, Sendable {

    public var receiver: CallReceiver

    public var methodName: String

    public var location: SourceLocation?

    /// Constructs its receiver type, which may have only an implicit initializer to target.
    public var isConstruction: Bool

    /// Recorded on the chance its receiver is a project type; not counted at all when it resolves to no member.
    public var isSpeculative: Bool

    public init(
        receiver: CallReceiver,
        methodName: String,
        location: SourceLocation? = nil,
        isConstruction: Bool = false,
        isSpeculative: Bool = false
    ) {
        self.receiver = receiver
        self.methodName = methodName
        self.location = location
        self.isConstruction = isConstruction
        self.isSpeculative = isSpeculative
    }

    public var receiverType: String? {
        if case .type(let name) = receiver { return name }
        return nil
    }

    public var asConstruction: CallSite {
        var copy = self
        copy.isConstruction = true
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case receiver, methodName, location, isConstruction, isSpeculative
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        receiver = try container.decode(CallReceiver.self, forKey: .receiver)
        methodName = try container.decode(String.self, forKey: .methodName)
        location = try container.decodeIfPresent(SourceLocation.self, forKey: .location)
        isConstruction = try container.decodeIfPresent(Bool.self, forKey: .isConstruction) ?? false
        isSpeculative = try container.decodeIfPresent(Bool.self, forKey: .isSpeculative) ?? false
    }

    /// Writes the flags only when set, keeping an ordinary call's encoding minimal.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(receiver, forKey: .receiver)
        try container.encode(methodName, forKey: .methodName)
        try container.encodeIfPresent(location, forKey: .location)
        if isConstruction {
            try container.encode(isConstruction, forKey: .isConstruction)
        }
        if isSpeculative {
            try container.encode(isSpeculative, forKey: .isSpeculative)
        }
    }
}
