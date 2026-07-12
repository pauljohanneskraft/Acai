import UMLCore
import UMLTreeSitter

// MARK: - TypeScript Interfaces

extension JSExtractor {

    // MARK: - Interface Declaration

    mutating func extractInterfaceDeclaration(_ node: Node, isExported: Bool) -> TypeDeclaration {
        let nodeLoc = loc(node)
        let nameNode = node.child(byFieldName: "name")
        let name = nameNode.map { text($0) } ?? "_Anonymous"

        let generics = extractTypeParameters(node)
        var inherited: [TypeReference] = []

        for child in node.children() {
            guard let childType = child.nodeType else { continue }
            if childType == "extends_type_clause" || childType == "extends_clause" {
                let refs = child.namedChildren().map { extractTypeReferenceFromExpression($0) }
                inherited.append(contentsOf: refs)
                recordSupertypeRelationships(from: name, to: refs, kind: .conformance)
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
                typeDecl.members.append(extractPropertySignature(child))
            case "method_signature":
                typeDecl.members.append(extractMethodSignature(child))
            case "call_signature":
                let params = extractParameters(child.child(byFieldName: "parameters") ?? child)
                let ret = extractReturnTypeAnnotation(child)
                typeDecl.members.append(
                    Member(name: "call", kind: .method, accessLevel: .internal, type: ret, parameters: params))
            case "construct_signature":
                let params = extractParameters(child.child(byFieldName: "parameters") ?? child)
                let ret = extractReturnTypeAnnotation(child)
                typeDecl.members.append(
                    Member(name: "new", kind: .initializer, accessLevel: .internal, type: ret, parameters: params))
            case "index_signature":
                break // Not modeled
            default:
                break
            }
        }
    }

    // MARK: - Property Signature

    func extractPropertySignature(_ node: Node) -> Member {
        let nodeLoc = loc(node)
        let nameNode = node.child(byFieldName: "name")
        let name = nameNode.map { text($0) } ?? ""

        var accessLevel: AccessLevel?
        var modifiers: [Modifier] = []

        if let acc = extractAccessibilityModifier(node) {
            accessLevel = acc
        }
        if node.hasDirectChildText("readonly", in: context) {
            modifiers.append(.readonly)
        }

        var propType = extractTypeAnnotation(node)
        if node.hasDirectChildText("?", in: context) {
            propType?.isOptional = true
        }

        return Member(
            name: name, kind: .property,
            accessLevel: accessLevel ?? .internal,
            modifiers: modifiers,
            type: propType,
            location: nodeLoc
        )
    }

    // MARK: - Method Signature

    func extractMethodSignature(_ node: Node) -> Member {
        let nodeLoc = loc(node)
        let nameNode = node.child(byFieldName: "name")
        let name = nameNode.map { text($0) } ?? ""

        let accessLevel = extractAccessibilityModifier(node)
        let generics = extractTypeParameters(node)
        let params: [Parameter]
        if let paramsNode = node.child(byFieldName: "parameters") {
            params = extractParameters(paramsNode)
        } else {
            params = []
        }
        let returnType = extractReturnTypeAnnotation(node)

        return Member(
            name: name, kind: .method,
            accessLevel: accessLevel ?? .internal,
            type: returnType,
            parameters: params,
            genericParameters: generics,
            location: nodeLoc
        )
    }
}
