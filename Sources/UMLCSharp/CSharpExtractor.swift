import Foundation
import UMLCore
import UMLTreeSitter

struct CSharpExtractor: TreeSitterExtracting {
    let context: SourceFileContext

    var types: [TypeDeclaration] = []
    var relationships: [Relationship] = []
    var freestandingFunctions: [Member] = []
    var currentNamespace: String?
    var declaredTypeNames: Set<String> = []

    init(source: String, fileName: String) {
        self.context = SourceFileContext(source: source, fileName: fileName)
    }

    mutating func walkSourceFile(_ node: Node) {
        for child in node.children() {
            visitTopLevel(child)
        }
    }

    mutating func visitTopLevel(_ node: Node) {
        switch node.nodeType {
        case "namespace_declaration":
            if let nameNode = node.child(byFieldName: "name") {
                let prevNamespace = currentNamespace
                currentNamespace = [currentNamespace, text(nameNode)].compactMap { $0 }.joined(separator: ".")
                if let body = node.child(byFieldName: "body") {
                    for child in body.children() {
                        visitTopLevel(child)
                    }
                }
                currentNamespace = prevNamespace
            }
        case "class_declaration", "interface_declaration", "struct_declaration", "record_declaration":
            if let type = extractTypeDeclaration(from: node) {
                types.append(type)
            }
        case "enum_declaration":
            if let type = extractEnum(from: node) {
                types.append(type)
            }
        default:
            break
        }
    }

    func extractTypeDeclaration(from node: Node) -> TypeDeclaration? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        
        let typeName = text(nameNode)
        let fqn = [currentNamespace, typeName].compactMap { $0 }.joined(separator: ".")
        
        var kind: TypeKind = .class
        if node.nodeType == "interface_declaration" { kind = .interface }
        else if node.nodeType == "struct_declaration" { kind = .struct }
        
        return TypeDeclaration(
            name: typeName,
            fullyQualifiedName: fqn,
            kind: kind,
            modifiers: [],
            members: [],
            location: location(of: node)
        )
    }

    func extractEnum(from node: Node) -> TypeDeclaration? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let typeName = text(nameNode)
        let fqn = [currentNamespace, typeName].compactMap { $0 }.joined(separator: ".")
        return TypeDeclaration(
            name: typeName,
            fullyQualifiedName: fqn,
            kind: .enum,
            modifiers: [],
            members: [],
            location: location(of: node)
        )
    }

    mutating func extract(from root: Node) -> CodeArtifact {
        declaredTypeNames = collectDeclaredTypeNames(
            from: root,
            declarationNodeTypes: [
                "class_declaration", "interface_declaration", "struct_declaration",
                "enum_declaration", "record_declaration"
            ],
            name: { $0.child(byFieldName: "name").map { self.text($0) } }
        )
        walkSourceFile(root)
        return buildArtifact(language: .cSharp)
    }
}
