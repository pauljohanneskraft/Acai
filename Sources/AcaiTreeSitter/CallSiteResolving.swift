import AcaiCore

/// Source-compatibility shim for the language extractors that have not yet been migrated off the
/// monolithic ``TreeSitterExtracting`` shape.
///
/// Every method here forwards to the value type that now owns the algorithm, so there is exactly
/// one implementation of each. What this protocol adds is the ability to reach them by *being* an
/// extractor, which is precisely the coupling the migration removes: a migrated plugin holds a
/// ``CallSiteResolver`` and a ``MemberCallResolver`` as stored properties instead, so its small
/// collaborator types can use them too.
///
/// Each language migrated off this protocol drops one conformer; it goes away with the last.
public protocol CallSiteResolving: TreeSitterExtracting, CallSiteSyntax {}

extension CallSiteResolving {

    public func extractCallSites(from body: Node?, scope: CallSiteScope) -> [CallSite] {
        CallSiteResolver(syntax: self).callSites(in: body, scope: scope)
    }

    public func resolveMemberCall(
        receiver: Node,
        methodName: String,
        grammar: MemberCallGrammar,
        scope: CallSiteScope,
        location: SourceLocation?
    ) -> CallSite? {
        MemberCallResolver(context: context, grammar: grammar).callSite(
            receiver: receiver, methodName: methodName, scope: scope, location: location
        )
    }
}
