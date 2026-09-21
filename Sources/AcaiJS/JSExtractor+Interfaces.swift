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
            guard let childType = child.nodeType else { continue }
            switch childType {
            case "property_signature":
                typeDecl.members.append(memberExtractor.propertySignature(child))
            case "method_signature":
                typeDecl.members.append(memberExtractor.methodSignature(child))
            case "call_signature":
                let params = parameterExtractor.parameters(child.child(byFieldName: "parameters") ?? child)
                let ret = typeReferences.extractReturnTypeAnnotation(child)
                typeDecl.members.append(
                    Member(name: "call", kind: .method, accessLevel: .internal, type: ret, parameters: params))
            case "construct_signature":
                let params = parameterExtractor.parameters(child.child(byFieldName: "parameters") ?? child)
                let ret = typeReferences.extractReturnTypeAnnotation(child)
                typeDecl.members.append(
                    Member(name: "new", kind: .initializer, accessLevel: .internal, type: ret, parameters: params))
            case "index_signature":
                break // Not modeled
            default:
                break
            }
        }
    }
}
