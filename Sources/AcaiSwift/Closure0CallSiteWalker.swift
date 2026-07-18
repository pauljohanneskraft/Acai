import SwiftSyntax
import AcaiCore

/// Collects call sites made through a closure's implicit `$0` receiver (`addedRelationships.map { "+ "
/// + $0.reportPhrase() }`) — the iteration-closure counterpart to `AccessorCallSiteWalker`. `$0`'s
/// type is resolved once by the caller, from the *iterated* expression's own receiver resolution
/// (`CallSiteCollector.receiverType`, via `iterationClosure(in:)`); this walker only binds it inside
/// the closure body, so it stays a plain identifier-shape match rather than re-deriving the type.
final class Closure0CallSiteWalker: SyntaxVisitor {
    private let elementReceiver: CallReceiver
    private let fileName: String
    private let sourceLocations = SourceLocationResolver()
    private(set) var collected: [CallSite] = []

    init(elementReceiver: CallReceiver, fileName: String) {
        self.elementReceiver = elementReceiver
        self.fileName = fileName
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "$0"
        else { return .visitChildren }
        collected.append(CallSite(
            receiver: elementReceiver,
            methodName: memberAccess.declName.baseName.text,
            location: sourceLocations.sourceLocation(of: node, fileName: fileName)
        ))
        return .visitChildren
    }
}
