import UMLCore
import UMLTreeSitter

extension RustExtractor {
    mutating func walkSourceFile(_ node: Node) {
        for child in node.namedChildren() {
            dispatchTopLevel(child)
        }
    }

    private mutating func dispatchTopLevel(_ node: Node) {
        switch node.nodeType {
        case "declaration_list":
            walkSourceFile(node)
        case "mod_item":
            walkModule(node)
        case "struct_item":
            if let declaration = extractStructDeclaration(node) {
                types.append(declaration)
            }
        case "enum_item":
            if let declaration = extractEnumDeclaration(node) {
                types.append(declaration)
            }
        case "trait_item":
            if let declaration = extractTraitDeclaration(node) {
                types.append(declaration)
            }
        case "type_item":
            if let declaration = extractTypeAliasDeclaration(node) {
                types.append(declaration)
            }
        case "impl_item":
            recordImplBlock(node)
        case "function_item":
            if let member = finalizeMember(
                extractFunctionMember(node, defaultAccessLevel: .private, treatNoSelfAsStatic: false),
                knownProperties: [:]
            ) {
                freestandingFunctions.append(member)
            }
        default:
            break
        }
    }

    private mutating func walkModule(_ node: Node) {
        guard let nameNode = node.child(byFieldName: "name") else { return }
        let previousNamespace = currentNamespace
        currentNamespace = qualifiedName(text(nameNode))
        if let body = node.child(byFieldName: "body") {
            walkSourceFile(body)
        }
        currentNamespace = previousNamespace
    }
}
