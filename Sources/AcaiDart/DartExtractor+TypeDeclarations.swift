import Foundation
import AcaiCore
import AcaiTreeSitter

// MARK: - Type Declarations

extension DartExtractor {

    mutating func extractClassDefinition(_ node: Node) -> TypeDeclaration? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = nameNode.text(in: context)
        let typeId = declarations.qualifiedName(name)
        let nodeLoc = node.location(in: context)
        let modifiers = typeReferences.classModifiers(node)
        let genericParams = typeReferences.typeParameters(from: node)
        var inheritedTypes: [TypeReference] = []

        if let superclassNode = node.child(byFieldName: "superclass") {
            for ref in typeReferences.superclassTypes(superclassNode) {
                inheritedTypes.append(ref)
                let label = ref.genericArguments.isEmpty ? nil
                    : "<" + ref.genericArguments.map(\.name).joined(separator: ", ") + ">"
                declarations.relationships.append(ref.relationship(kind: .inheritance, source: typeId, label: label))
            }
        }

        // Mixins may be nested inside the superclass node.
        var mixinNodes: [Node] = node.allChildren(withType: "mixins")
        if let superclassNode = node.child(byFieldName: "superclass") {
            mixinNodes += superclassNode.allChildren(withType: "mixins")
        }
        for mixinsNode in mixinNodes {
            for ref in typeReferences.typeList(mixinsNode) {
                inheritedTypes.append(ref)
                declarations.relationships.append(ref.relationship(kind: .inheritance, source: typeId))
            }
        }

        if let interfacesNode = node.child(byFieldName: "interfaces") {
            for ref in typeReferences.typeList(interfacesNode) {
                inheritedTypes.append(ref)
                declarations.relationships.append(ref.relationship(kind: .conformance, source: typeId))
            }
        }

        var members: [Member] = []
        var nestedTypes: [TypeDeclaration] = []

        if let bodyNode = node.child(byFieldName: "body") {
            extractClassBody(bodyNode, members: &members, nestedTypes: &nestedTypes, parentName: name)
        }

        return TypeDeclaration(
            id: typeId, name: name, qualifiedName: typeId, kind: .class,
            accessLevel: DartName(name).accessLevel,
            modifiers: modifiers,
            genericParameters: genericParams, inheritedTypes: inheritedTypes,
            members: members, nestedTypes: nestedTypes,
            annotations: annotations.annotations(of: node),
            namespace: declarations.currentNamespace, location: nodeLoc
        )
    }

    // MARK: - Enum Declaration

    mutating func extractEnumDeclaration(_ node: Node) -> TypeDeclaration? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = nameNode.text(in: context)
        let typeId = declarations.qualifiedName(name)
        let nodeLoc = node.location(in: context)
        var inheritedTypes: [TypeReference] = []

        for child in node.children() where child.nodeType == "mixins" {
            for ref in typeReferences.typeList(child) {
                inheritedTypes.append(ref)
                declarations.relationships.append(ref.relationship(kind: .inheritance, source: typeId))
            }
        }

        for child in node.children() where child.nodeType == "interfaces" {
            for ref in typeReferences.typeList(child) {
                inheritedTypes.append(ref)
                declarations.relationships.append(ref.relationship(kind: .conformance, source: typeId))
            }
        }

        var enumCases: [EnumCase] = []
        var members: [Member] = []

        if let bodyNode = node.child(byFieldName: "body") {
            extractEnumBody(bodyNode, enumCases: &enumCases, members: &members, parentName: name)
        }

        return TypeDeclaration(
            id: typeId, name: name, qualifiedName: typeId, kind: .enum,
            accessLevel: DartName(name).accessLevel,
            inheritedTypes: inheritedTypes,
            members: members, enumCases: enumCases,
            annotations: annotations.annotations(of: node),
            namespace: declarations.currentNamespace, location: nodeLoc
        )
    }

    // MARK: - Mixin Declaration

    private mutating func extractMixinOnConstraints(
        _ node: Node, typeId: String
    ) -> [TypeReference] {
        var refs: [TypeReference] = []
        var seenOnKeyword = false
        for child in node.children() {
            if !child.isNamed && child.text(in: context) == "on" {
                seenOnKeyword = true
                continue
            }
            guard seenOnKeyword, let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "type_not_void_list", "_type_not_void_list":
                for ref in typeReferences.typeListFromChildren(child) {
                    refs.append(ref)
                    declarations.relationships.append(ref.relationship(kind: .inheritance, source: typeId))
                }
                seenOnKeyword = false
            case "type_identifier", "generic_type":
                if let ref = typeReferences.typeReference(child) {
                    refs.append(ref)
                    declarations.relationships.append(ref.relationship(kind: .inheritance, source: typeId))
                }
            default:
                seenOnKeyword = false
            }
        }
        return refs
    }

    mutating func extractMixinDeclaration(_ node: Node) -> TypeDeclaration? {
        var name = ""
        for child in node.children() where child.nodeType == "identifier" && name.isEmpty {
            name = child.text(in: context)
        }
        guard !name.isEmpty else { return nil }
        let typeId = declarations.qualifiedName(name)
        let genericParams = typeReferences.typeParametersFromChildren(node)
        var inheritedTypes = extractMixinOnConstraints(node, typeId: typeId)

        for child in node.children() where child.nodeType == "interfaces" {
            for ref in typeReferences.typeList(child) {
                inheritedTypes.append(ref)
                declarations.relationships.append(ref.relationship(kind: .conformance, source: typeId))
            }
        }

        var members: [Member] = []
        var nestedTypes: [TypeDeclaration] = []
        for child in node.children() where child.nodeType == "class_body" {
            extractClassBody(child, members: &members, nestedTypes: &nestedTypes, parentName: name)
        }

        return TypeDeclaration(
            id: typeId, name: name, qualifiedName: typeId, kind: .mixin,
            accessLevel: DartName(name).accessLevel,
            genericParameters: genericParams, inheritedTypes: inheritedTypes,
            members: members, nestedTypes: nestedTypes,
            annotations: annotations.annotations(of: node),
            namespace: declarations.currentNamespace, location: node.location(in: context)
        )
    }

    // MARK: - Extension Declaration

    mutating func extractExtensionDeclaration(_ node: Node) -> TypeDeclaration? {
        let name = node.child(byFieldName: "name").map { $0.text(in: context) }
        let extendedType = node.child(byFieldName: "class").map { $0.text(in: context) }
        let nodeLoc = node.location(in: context)

        let displayName = name ?? (extendedType.map { "\($0)Extension" }) ?? "Extension"

        var members: [Member] = []
        var nestedTypes: [TypeDeclaration] = []

        if let bodyNode = node.child(byFieldName: "body") {
            extractClassBody(bodyNode, members: &members, nestedTypes: &nestedTypes, parentName: displayName)
        }

        let typeId = declarations.qualifiedName(displayName)
        return TypeDeclaration(
            id: typeId, name: displayName, qualifiedName: typeId,
            kind: .extension, accessLevel: DartName(displayName).accessLevel,
            members: members, nestedTypes: nestedTypes,
            annotations: annotations.annotations(of: node),
            extensionOf: extendedType,
            namespace: declarations.currentNamespace, location: nodeLoc
        )
    }

    // MARK: - Extension Type Declaration

    mutating func extractExtensionTypeDeclaration(_ node: Node) -> TypeDeclaration? {
        var name = ""
        for child in node.children() {
            if child.nodeType == "identifier" && name.isEmpty {
                name = child.text(in: context)
            }
        }
        guard !name.isEmpty else { return nil }
        let typeId = declarations.qualifiedName(name)
        let nodeLoc = node.location(in: context)
        var inheritedTypes: [TypeReference] = []

        for child in node.children() where child.nodeType == "interfaces" {
            for ref in typeReferences.typeList(child) {
                inheritedTypes.append(ref)
                declarations.relationships.append(ref.relationship(kind: .conformance, source: typeId))
            }
        }

        var members: [Member] = []
        var nestedTypes: [TypeDeclaration] = []

        for child in node.children() {
            if child.nodeType == "extension_body" || child.nodeType == "class_body" {
                extractClassBody(child, members: &members, nestedTypes: &nestedTypes, parentName: name)
            }
        }

        return TypeDeclaration(
            id: typeId, name: name, qualifiedName: typeId, kind: .class,
            accessLevel: DartName(name).accessLevel,
            inheritedTypes: inheritedTypes,
            members: members, nestedTypes: nestedTypes,
            annotations: annotations.annotations(of: node),
            namespace: declarations.currentNamespace, location: nodeLoc
        )
    }
}
