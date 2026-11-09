import SwiftSyntax
import AcaiCore

/// A Swift call expression's argument list, as the two call syntaxes that have one both spell it.
/// `SubscriptCallExprSyntax` and `FunctionCallExprSyntax` share no SwiftSyntax protocol carrying
/// these, so this names what they have in common.
protocol CallArgumentSyntax {
    var arguments: LabeledExprListSyntax { get }
    var trailingClosure: ClosureExprSyntax? { get }
    var additionalTrailingClosures: MultipleTrailingClosureElementListSyntax { get }
}

extension CallArgumentSyntax {
    /// The call's arguments as ``CallSite/arguments`` records them: one entry per argument, carrying
    /// its label where the call spells one. A trailing closure fills the parameter whose label the
    /// call syntax omits, so it contributes an unlabelled entry — keeping the arity right, which is
    /// what overload selection needs.
    var callSiteArguments: [String?] {
        var labels: [String?] = arguments.map { $0.label?.text }
        if trailingClosure != nil { labels.append(nil) }
        labels.append(contentsOf: additionalTrailingClosures.map { $0.label.text })
        return labels
    }
}

extension FunctionCallExprSyntax: CallArgumentSyntax {}

extension SubscriptCallExprSyntax: CallArgumentSyntax {}
