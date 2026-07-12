import SwiftSyntax

/// One pre-pass over a Swift source tree gathering each protocol's *requirement* properties
/// (`var x: T { get [set] }`) with a provable simple type — keyed by protocol name, so
/// ``DeclarationVisitor`` can seed a protocol extension's property map with them (the extension's own
/// member list never carries them, since they're declared on the protocol, not the extension).
///
/// Fixes the gap where a protocol extension's default implementation calls a method through a
/// requirement property (`extension Hosting { func undo() { history.undo() } }`, `history` declared
/// only on `protocol Hosting`) — previously unresolvable, dropping the call and false-flagging its
/// target as dead code.
final class ProtocolPropertyCollector: SyntaxVisitor {
    private(set) var propertiesByProtocol: [String: [String: String]] = [:]

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        var properties: [String: String] = [:]
        for member in node.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            for binding in variable.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let typeName = binding.typeAnnotation?.type.as(IdentifierTypeSyntax.self)?.name.text
                else { continue }
                properties[name] = typeName
            }
        }
        propertiesByProtocol[node.name.text] = properties
        return .visitChildren
    }
}
