import AcaiCore
import AcaiTreeSitter

// MARK: - TypeScript Interfaces

extension JSExtractor {

    // MARK: - Interface Declaration

    mutating func extractInterfaceDeclaration(_ node: Node, isExported: Bool) -> TypeDeclaration {
        let nodeLoc = node.location(in: context)
        let nameNode = node.child(byFieldName: "name")
        let name = nameNode.map { $0.text(in: context) } ?? "_Anonymous"

        let generics = typeReferences.extractTypeParameters(node)
        var inherited: [TypeReference] = []

        for child in node.children() {
            guard let childType = child.nodeType else { continue }
            if childType == "extends_type_clause" || childType == "extends_clause" {
                let refs = child.namedChildren().map { typeReferences.extractTypeReferenceFromExpression($0) }
                inherited.append(contentsOf: refs)
                declarations.recordSupertypeRelationships(from: name, to: refs, kind: .conformance)
            }
        }

        var typeDecl = TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .interface,
            accessLevel: isExported ? .public : .internal,
            genericParameters: generics,
            inheritedTypes: inherited,
            location: nodeLoc
        )

        if let body = node.child(byFieldName: "body") {
            parseInterfaceBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Interface Body

    private func parseInterfaceBody(_ bodyNode: Node, into typeDecl: inout TypeDeclaration) {
        for child in bodyNode.namedChildren() {
            guard var member = interfaceMember(child) else { continue }
            member.documentation = documentation.documentation(above: child, in: context)
            typeDecl.members.append(member)
        }
    }

    /// `index_signature` is not modelled, and neither is anything else unlisted.
    private func interfaceMember(_ node: Node) -> Member? {
        switch node.nodeType {
        case "property_signature":
            return memberExtractor.propertySignature(node)
        case "method_signature":
            return memberExtractor.methodSignature(node)
        case "call_signature":
            return signatureMember(node, name: "call", kind: .method)
        case "construct_signature":
            return signatureMember(node, name: "new", kind: .initializer)
        default:
            return nil
        }
    }

    private func signatureMember(_ node: Node, name: String, kind: MemberKind) -> Member {
        Member(
            name: name, kind: kind, accessLevel: .internal,
            type: typeReferences.extractReturnTypeAnnotation(node),
            parameters: parameterExtractor.parameters(node.child(byFieldName: "parameters") ?? node)
        )
    }
}
