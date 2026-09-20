import AcaiCore

/// Superseded by ``CallSiteSyntax`` plus ``CallSiteResolver``, which a plugin holds instead of
/// conforming to. Kept so the plugins not yet migrated compile unchanged; deleted with the last
/// conformer.
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
