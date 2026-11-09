import SwiftSyntax
import AcaiCore

extension FunctionCallExprSyntax {
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

extension SubscriptCallExprSyntax {
    /// The subscript's arguments, labelled as ``FunctionCallExprSyntax/callSiteArguments``.
    var callSiteArguments: [String?] {
        var labels: [String?] = arguments.map { $0.label?.text }
        if trailingClosure != nil { labels.append(nil) }
        labels.append(contentsOf: additionalTrailingClosures.map { $0.label.text })
        return labels
    }
}
