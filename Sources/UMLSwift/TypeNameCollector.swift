import SwiftSyntax

/// One pre-pass over a Swift source tree gathering the simple names of every declared type
/// (class/struct/enum/protocol/actor, plus extended types). Run before ``DeclarationVisitor``
/// so call-site resolution sees the *complete* set of type names up front — including
/// forward-declared siblings — rather than only types visited so far.
final class TypeNameCollector: SyntaxVisitor {
    private(set) var names: Set<String> = []

    static func collect(from tree: some SyntaxProtocol) -> Set<String> {
        let collector = TypeNameCollector(viewMode: .sourceAccurate)
        collector.walk(tree)
        return collector.names
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        names.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        names.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        names.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        names.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        names.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        names.insert(node.extendedType.trimmedDescription)
        return .visitChildren
    }
}
