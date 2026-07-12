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
    /// Every local name declared so far, *whether or not* its type was provable — so a local whose
    /// type inference failed (an ambiguous overload, a tuple return) isn't mistaken for the enclosing
    /// type's own property when `receiverMap` has no entry for it (mirrors `DeclarationVisitor`'s
    /// `callSiteKnownLocalNames`).
    private var knownLocalNames: Set<String>
    private let enclosingTypeName: String?
    private let methodReturnTypes: [String: String]
    private let fileName: String
    private(set) var collected: [CallSite] = []

    init(
        collector: CallSiteCollector, propertyMap: [String: String],
        enclosingTypeName: String?, methodReturnTypes: [String: String] = [:], fileName: String
    ) {
        self.collector = collector
        self.receiverMap = propertyMap
        self.knownLocalNames = []
        self.enclosingTypeName = enclosingTypeName
        self.methodReturnTypes = methodReturnTypes
        self.fileName = fileName
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
            knownLocalNames.insert(name)
            if let local = collector.localBinding(from: binding, methodReturnTypes: methodReturnTypes) {
                receiverMap[local.name] = local.type
            }
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let site = collector.callSite(
            from: node, propertyMap: receiverMap,
            enclosingTypeName: enclosingTypeName, knownLocalNames: knownLocalNames, fileName: fileName) {
            collected.append(site)
        }
        return .visitChildren
    }
}
