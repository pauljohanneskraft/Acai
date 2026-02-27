import Foundation
import UMLCore
import UMLTreeSitter

// MARK: - Type Declarations

extension DartExtractor {

    mutating func extractClassDefinition(_ node: Node) -> TypeDeclaration? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = text(nameNode)
        let typeId = qualifiedName(name)
        let nodeLoc = loc(node)
        let modifiers = extractClassModifiers(node)
        let genericParams = extractTypeParameters(from: node)
        var inheritedTypes: [TypeReference] = []

        // Superclass (extends).
        if let superclassNode = node.child(byFieldName: "superclass") {
            for ref in extractSuperclassTypes(superclassNode) {
                inheritedTypes.append(ref)
                let label = ref.genericArguments.isEmpty ? nil
                    : "<" + ref.genericArguments.map(\.name).joined(separator: ", ") + ">"
                relationships.append(Relationship(
                    kind: .inheritance, source: typeId, target: ref.name, label: label))
            }
        }

        // Mixins (with).
        for child in node.children() where child.nodeType == "mixins" {
            for ref in extractTypeList(child) {
                inheritedTypes.append(ref)
                relationships.append(Relationship(
                    kind: .inheritance, source: typeId, target: ref.name))
            }
        }

        // Interfaces (implements).
        if let interfacesNode = node.child(byFieldName: "interfaces") {
            for ref in extractTypeList(interfacesNode) {
                inheritedTypes.append(ref)
                relationships.append(Relationship(
                    kind: .conformance, source: typeId, target: ref.name))
            }
        }

        var members: [Member] = []
        var nestedTypes: [TypeDeclaration] = []

        if let bodyNode = node.child(byFieldName: "body") {
            extractClassBody(bodyNode, members: &members, nestedTypes: &nestedTypes, parentName: name)
        }

        return TypeDeclaration(
            id: typeId, name: name, qualifiedName: typeId, kind: .class,
            accessLevel: accessLevel(for: name),
            modifiers: modifiers,
            genericParameters: genericParams, inheritedTypes: inheritedTypes,
            members: members, nestedTypes: nestedTypes,
            namespace: currentNamespace, location: nodeLoc
        )
    }

    // MARK: - Enum Declaration

    mutating func extractEnumDeclaration(_ node: Node) -> TypeDeclaration? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = text(nameNode)
        let typeId = qualifiedName(name)
        let nodeLoc = loc(node)
        var inheritedTypes: [TypeReference] = []

        // Mixins.
        for child in node.children() where child.nodeType == "mixins" {
            for ref in extractTypeList(child) {
                inheritedTypes.append(ref)
                relationships.append(Relationship(
                    kind: .inheritance, source: typeId, target: ref.name))
            }
        }

        // Interfaces.
        for child in node.children() where child.nodeType == "interfaces" {
            for ref in extractTypeList(child) {
                inheritedTypes.append(ref)
                relationships.append(Relationship(
                    kind: .conformance, source: typeId, target: ref.name))
            }
        }

        var enumCases: [EnumCase] = []
        var members: [Member] = []

        if let bodyNode = node.child(byFieldName: "body") {
            extractEnumBody(bodyNode, enumCases: &enumCases, members: &members, parentName: name)
        }

        return TypeDeclaration(
            id: typeId, name: name, qualifiedName: typeId, kind: .enum,
            accessLevel: accessLevel(for: name),
            inheritedTypes: inheritedTypes,
            members: members, enumCases: enumCases,
            namespace: currentNamespace, location: nodeLoc
        )
    }

    // MARK: - Mixin Declaration

    mutating func extractMixinDeclaration(_ node: Node) -> TypeDeclaration? {
        // Mixin: optional(metadata) optional(base) 'mixin' identifier
        // optional(type_parameters) optional('on' type_list)
        // optional(interfaces) class_body
        var name = ""
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            if nodeType == "identifier" && name.isEmpty {
                name = text(child)
            }
        }
        guard !name.isEmpty else { return nil }
        let typeId = qualifiedName(name)
        let nodeLoc = loc(node)
        let genericParams = extractTypeParametersFromChildren(node)
        var inheritedTypes: [TypeReference] = []

        // 'on' constraint types.
        for child in node.children() {
            if child.nodeType == "type_not_void_list" || child.nodeType == "_type_not_void_list" {
                for ref in extractTypeListFromChildren(child) {
                    inheritedTypes.append(ref)
                    relationships.append(Relationship(
                        kind: .inheritance, source: typeId, target: ref.name))
                }
            }
        }

        // Interfaces.
        for child in node.children() where child.nodeType == "interfaces" {
            for ref in extractTypeList(child) {
                inheritedTypes.append(ref)
                relationships.append(Relationship(
                    kind: .conformance, source: typeId, target: ref.name))
            }
        }

        var members: [Member] = []
        var nestedTypes: [TypeDeclaration] = []

        // The body is a class_body node.
        for child in node.children() where child.nodeType == "class_body" {
            extractClassBody(child, members: &members, nestedTypes: &nestedTypes, parentName: name)
        }

        return TypeDeclaration(
            id: typeId, name: name, qualifiedName: typeId, kind: .mixin,
            accessLevel: accessLevel(for: name),
            genericParameters: genericParams, inheritedTypes: inheritedTypes,
            members: members, nestedTypes: nestedTypes,
            namespace: currentNamespace, location: nodeLoc
        )
    }

    // MARK: - Extension Declaration

    mutating func extractExtensionDeclaration(_ node: Node) -> TypeDeclaration? {
        let name = node.child(byFieldName: "name").map { text($0) }
        let extendedType = node.child(byFieldName: "class").map { text($0) }
        let nodeLoc = loc(node)

        let displayName = name ?? (extendedType.map { "\($0)Extension" }) ?? "Extension"

        var members: [Member] = []
        var nestedTypes: [TypeDeclaration] = []

        if let bodyNode = node.child(byFieldName: "body") {
            extractClassBody(bodyNode, members: &members, nestedTypes: &nestedTypes, parentName: displayName)
        }

        return TypeDeclaration(
            id: qualifiedName(displayName), name: displayName, qualifiedName: qualifiedName(displayName),
            kind: .extension,
            members: members, nestedTypes: nestedTypes,
            extensionOf: extendedType,
            namespace: currentNamespace, location: nodeLoc
        )
    }

    // MARK: - Extension Type Declaration

    mutating func extractExtensionTypeDeclaration(_ node: Node) -> TypeDeclaration? {
        var name = ""
        for child in node.children() {
            if child.nodeType == "identifier" && name.isEmpty {
                name = text(child)
            }
        }
        guard !name.isEmpty else { return nil }
        let typeId = qualifiedName(name)
        let nodeLoc = loc(node)
        var inheritedTypes: [TypeReference] = []

        for child in node.children() where child.nodeType == "interfaces" {
            for ref in extractTypeList(child) {
                inheritedTypes.append(ref)
                relationships.append(Relationship(
                    kind: .conformance, source: typeId, target: ref.name))
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
            accessLevel: accessLevel(for: name),
            inheritedTypes: inheritedTypes,
            members: members, nestedTypes: nestedTypes,
            namespace: currentNamespace, location: nodeLoc
        )
    }
}
