import SwiftSyntax
import UMLCore

/// Collects the resolvable call sites made inside a computed property's accessor bodies
/// (`var body: some View { … }`, explicit `get`/`set`).
///
/// Runs as a dedicated walk rather than having the main `DeclarationVisitor` descend into the
/// accessor: member extraction for a `var` stays a single `.skipChildren` step, and — unlike the
/// coupling metrics' `TypeReferenceCollector`, which is deliberately *not* run over accessor bodies
/// to avoid overflowing the stack on deep view trees — this only walks the body once, gathering call
/// sites via the shared `CallSiteCollector`. Unresolvable receivers (SwiftUI modifier chains like
/// `Text(…).padding()`) are dropped by the collector, so only real, resolvable calls are recorded.
final class AccessorCallSiteWalker: SyntaxVisitor {
    private let collector: CallSiteCollector
    /// Stored properties seeded up front, plus locals declared in the accessor recorded as they're
    /// visited — so `local.method()` inside a `body` resolves, just as in a function body.
    private var receiverMap: [String: String]
    private let fileName: String
    private(set) var collected: [CallSite] = []

    init(collector: CallSiteCollector, propertyMap: [String: String], fileName: String) {
        self.collector = collector
        self.receiverMap = propertyMap
        self.fileName = fileName
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            if let local = collector.localBinding(from: binding) {
                receiverMap[local.name] = local.type
            }
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let site = collector.callSite(from: node, propertyMap: receiverMap, fileName: fileName) {
            collected.append(site)
        }
        return .visitChildren
    }
}
