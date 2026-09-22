import AcaiCore
import AcaiTreeSitter

// MARK: - Source File

extension KotlinExtractor {

    // MARK: - Source File

    private enum SourceFileAction {
        case setPackage
        case classDeclaration
        case objectDeclaration
        case functionDeclaration
        case propertyDeclaration
        case typeAlias
    }

    private static let sourceFileDispatch: [String: SourceFileAction] = [
        "package_header": .setPackage,
        "class_declaration": .classDeclaration,
        "object_declaration": .objectDeclaration,
        "function_declaration": .functionDeclaration,
        "property_declaration": .propertyDeclaration,
        "type_alias": .typeAlias
    ]

    mutating func walkSourceFile(_ node: Node) {
        for (child, action) in NodeDispatch(Self.sourceFileDispatch).matches(in: node) {
            performSourceFileAction(action, on: child)
        }
    }

    private mutating func performSourceFileAction(_ action: SourceFileAction, on node: Node) {
        switch action {
        case .setPackage:
            if let packageName = node.firstChild(withType: "identifier")?.text(in: context) {
                _ = declarations.enter(namespace: packageName)
            }
        case .classDeclaration:
            handleClassDeclaration(node)
        case .objectDeclaration:
            if let typeDecl = extractObjectDeclaration(node) {
                declarations.types.append(typeDecl)
            }
        case .functionDeclaration:
            declarations.freestandingFunctions.append(
                extractFunctionDeclaration(node)
            )
        case .propertyDeclaration:
            declarations.globalVariables.append(memberExtractor.propertyDeclaration(node))
        case .typeAlias:
            if let typeDecl = extractTypeAlias(node) {
                declarations.types.append(typeDecl)
            }
        }
    }

    private mutating func handleClassDeclaration(_ child: Node) {
        if child.hasDirectChildText("interface", in: context) {
            if let typeDecl = extractInterfaceDeclaration(child) {
                declarations.types.append(typeDecl)
            }
        } else {
            if let typeDecl = extractClassDeclaration(child) {
                declarations.types.append(typeDecl)
            }
        }
    }
}
