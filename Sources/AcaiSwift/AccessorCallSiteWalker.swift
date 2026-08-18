import SwiftSyntax
import AcaiCore

/// Collects call sites inside a computed property's accessor bodies (`var body: some View { … }`).
/// Runs as a dedicated walk rather than having `DeclarationVisitor` descend into the accessor, so
/// member extraction for a `var` stays a single `.skipChildren` step.
final class AccessorCallSiteWalker: SyntaxVisitor {
    private let collector: CallSiteCollector
    /// Seeded with stored properties; locals are added as they're visited, so `local.method()`
    /// inside a `body` resolves just as in a function body.
    private var receiverMap: [String: String]
    private var knownLocalNames: Set<String>
    private let enclosingTypeName: String?
    private let methodReturnTypes: [String: String]
    /// The enclosing type's own method names, so a bare method-reference-as-value (`Button(action:
    /// chooseFile)`) resolves the same way it does in a plain function body.
    private let methodNames: Set<String>
    private let fileName: String
    private(set) var collected: [CallSite] = []

    init(
        collector: CallSiteCollector, propertyMap: [String: String],
        enclosingTypeName: String?, methodReturnTypes: [String: String] = [:],
        methodNames: Set<String> = [], fileName: String
    ) {
        self.collector = collector
        self.receiverMap = propertyMap
        self.knownLocalNames = []
        self.enclosingTypeName = enclosingTypeName
        self.methodReturnTypes = methodReturnTypes
        self.methodNames = methodNames
        self.fileName = fileName
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
            knownLocalNames.insert(name)
            // Only `.concrete` origins are usable here — this walker has no
            // `localReceiverOriginMap` equivalent for a `.deferred` one.
            if let local = collector.localBinding(from: binding, methodReturnTypes: methodReturnTypes),
               case .concrete(let type) = local.origin {
                receiverMap[local.name] = type
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

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        guard collector.isBareReferenceUse(node),
              let site = collector.methodReference(
                from: node, propertyMap: receiverMap, methodNames: methodNames, fileName: fileName)
        else { return .visitChildren }
        collected.append(site)
        return .visitChildren
    }
}
