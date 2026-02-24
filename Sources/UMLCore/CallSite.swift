/// A statically-observable call to a method or free function, recorded
/// inside a `Member`'s body during source analysis.
///
/// Parsers populate `Member.callSites` when they can determine the call target
/// from the source text. Dynamic dispatch (e.g. protocol witness calls through an
/// existential, closures stored in variables) may not be captured.
public struct CallSite: Codable, Equatable, Hashable, Sendable {

    /// The static type of the receiver, if determinable from the source.
    ///
    /// `nil` for free-function calls or when the receiver is a generic
    /// parameter / protocol existential and the concrete type is unknown.
    public var receiverType: String?

    /// The name of the method or function being called.
    public var methodName: String

    /// Source location of the call expression.
    public var location: SourceLocation?

    public init(
        receiverType: String? = nil,
        methodName: String,
        location: SourceLocation? = nil
    ) {
        self.receiverType = receiverType
        self.methodName = methodName
        self.location = location
    }
}
