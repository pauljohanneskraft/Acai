import SwiftSyntax
import AcaiCore

/// What `FunctionCallExprSyntax` and `SubscriptCallExprSyntax` share but SwiftSyntax doesn't name.
protocol CallArgumentSyntax {
    var arguments: LabeledExprListSyntax { get }
    var trailingClosure: ClosureExprSyntax? { get }
    var additionalTrailingClosures: MultipleTrailingClosureElementListSyntax { get }
}

extension CallArgumentSyntax {
    /// A trailing closure counts as one unlabelled argument.
    var callSiteArguments: [String?] {
        var labels: [String?] = arguments.map { $0.label?.text }
        if trailingClosure != nil { labels.append(nil) }
        labels.append(contentsOf: additionalTrailingClosures.map { $0.label.text })
        return labels
    }
}

extension FunctionCallExprSyntax: CallArgumentSyntax {}

extension SubscriptCallExprSyntax: CallArgumentSyntax {}
