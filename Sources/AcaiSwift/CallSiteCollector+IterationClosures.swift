import SwiftSyntax
import AcaiCore

/// Closure-`$0` receiver-type binding for implicit-parameter Sequence/Collection iteration closures
/// (`addedRelationships.map { $0.reportPhrase() }`) — split out of `CallSiteCollector.swift` to keep
/// that file under the project's length limits.
extension CallSiteCollector {
    /// Sequence/Collection methods whose (possibly-implicit) closure parameter is the receiver's
    /// element type — the shape `iterationClosure(in:)` recognises for closure-`$0` receiver binding.
    private var iterationMethodNames: Set<String> {
        ["map", "compactMap", "flatMap", "filter", "forEach", "allSatisfy", "contains", "first", "sorted"]
    }

    /// The receiver expression and trailing closure of an implicit-`$0` iteration call (`.map { "+ " +
    /// $0.reportPhrase() }`) — `nil` for a closure with an explicit parameter list (`{ item in ... }`)
    /// or a method outside `iterationMethodNames`.
    func iterationClosure(in call: FunctionCallExprSyntax) -> (receiverBase: ExprSyntax, closure: ClosureExprSyntax)? {
        guard let closure = call.trailingClosure, closure.signature == nil,
              let memberAccess = unwrappedCallee(call.calledExpression).as(MemberAccessExprSyntax.self),
              iterationMethodNames.contains(memberAccess.declName.baseName.text),
              let base = memberAccess.base
        else { return nil }
        return (base, closure)
    }

    /// The element type of an array-typed receiver expression — resolves a bare `varName` to a
    /// same-type stored property's array element, or defers to the post-merge pass via
    /// `.ownPropertyElement` when declared in a sibling extension file. Used only for the
    /// iteration-closure `$0` binding — an array's element is never a valid direct-call receiver.
    func arrayElementReceiverType(
        of expr: ExprSyntax, arrayElementPropertyMap: [String: String], enclosingTypeName: String?,
        knownLocalNames: Set<String>
    ) -> CallReceiver? {
        guard let name = bareLowercaseIdentifier(expr) else { return nil }
        if let elementType = arrayElementPropertyMap[name] {
            return .type(elementType)
        }
        guard enclosingTypeName != nil, !knownLocalNames.contains(name) else { return nil }
        return .ownPropertyElement(propertyName: name)
    }
}
