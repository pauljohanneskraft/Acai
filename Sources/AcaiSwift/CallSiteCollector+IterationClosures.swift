import SwiftSyntax
import AcaiCore

/// Closure-`$0` receiver-type binding for implicit-parameter Sequence/Collection iteration closures
/// (`addedRelationships.map { $0.reportPhrase() }`).
extension CallSiteCollector {
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

    /// The element type of an array-typed receiver expression, resolving a bare `varName` to a
    /// same-type stored property's array element (or deferring post-merge via `.ownPropertyElement`).
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
