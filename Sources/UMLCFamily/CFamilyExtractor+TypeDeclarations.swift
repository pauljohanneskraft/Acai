import UMLCore
import UMLTreeSitter

// MARK: - Records (struct / union / class), enums, typedefs

extension CFamilyExtractor {

    /// Extracts a `struct`/`union`/`class` specifier into a `TypeDeclaration`. Returns `nil` for an
    /// anonymous specifier (those are named by their enclosing `typedef`, handled separately).
    mutating func extractRecord(_ node: Node, typedefName: String? = nil) -> TypeDeclaration? {
        guard let name = node.child(byFieldName: "name").map({ text($0) }) ?? typedefName else {
            return nil
        }
        let typeId = qualifiedName(name)
        let isClass = node.nodeType == "class_specifier"
        let kind: TypeKind = isClass ? .class : .struct
        let defaultAccess: AccessLevel = isClass ? .private : .public

        let inheritedTypes = baseClasses(of: node)
        recordSupertypeRelationships(from: typeId, to: inheritedTypes, kind: .inheritance)

        var members: [Member] = []
        var nestedTypes: [TypeDeclaration] = []
        if let body = node.child(byFieldName: "body") {
            // Qualify nested records/enums against this record's id so a `struct Inner` nested in
            // `Outer` becomes `Outer.Inner` rather than colliding with a top-level `Inner`. Only
            // nested-type ids consult the namespace inside a record body, so top-level records are
            // unaffected (the record's own `namespace` field is read after this restores).
            let savedNamespace = currentNamespace
            currentNamespace = typeId
            defer { currentNamespace = savedNamespace }
            extractRecordBody(body, ownerName: name, defaultAccess: defaultAccess,
                              members: &members, nestedTypes: &nestedTypes)
        }

        // A C++ record with a pure-virtual member (`… = 0;`, recorded as an `.abstract` method) is
        // an abstract base class — the C++ idiom for an interface/protocol. Lift that onto the type
        // so the agnostic abstractness metric counts it like a Java interface.
        let isAbstract = members.contains { $0.modifiers.contains(.abstract) }

        return TypeDeclaration(
            id: typeId, name: name, qualifiedName: typeId, kind: kind,
            accessLevel: .public, modifiers: isAbstract ? [.abstract] : [],
            inheritedTypes: inheritedTypes,
            members: members, nestedTypes: nestedTypes,
            namespace: currentNamespace, location: loc(node)
        )
    }

    private func baseClasses(of node: Node) -> [TypeReference] {
        guard let clause = node.allChildren(withType: "base_class_clause").first else { return [] }
        var refs: [TypeReference] = []
        for child in clause.namedChildren() {
            switch child.nodeType {
            case "type_identifier", "qualified_identifier", "scoped_type_identifier", "template_type":
                if let ref = baseTypeReference(child) { refs.append(ref) }
            default:
                break
            }
        }
        return refs
    }

    // MARK: - Enums

    mutating func extractEnum(_ node: Node, typedefName: String? = nil) -> TypeDeclaration? {
        guard let name = node.child(byFieldName: "name").map({ text($0) }) ?? typedefName else {
            return nil
        }
        let typeId = qualifiedName(name)
        var cases: [EnumCase] = []
        if let body = node.child(byFieldName: "body") {
            for enumerator in body.namedChildren() where enumerator.nodeType == "enumerator" {
                if let caseName = enumerator.child(byFieldName: "name").map({ text($0) }) {
                    let rawValue = enumerator.child(byFieldName: "value").map { text($0) }
                    cases.append(EnumCase(name: caseName, rawValue: rawValue, location: loc(enumerator)))
                }
            }
        }
        return TypeDeclaration(
            id: typeId, name: name, qualifiedName: typeId, kind: .enum,
            accessLevel: .public, enumCases: cases,
            namespace: currentNamespace, location: loc(node)
        )
    }

    // MARK: - Typedefs

    /// Handles `typedef …`. An anonymous record/enum (`typedef struct { … } Foo;`) is named by the
    /// typedef; a plain alias (`typedef uint32_t Handle;`) becomes a `typeAlias` whose underlying
    /// type drives a dependency edge in enrichment.
    mutating func extractTypedef(_ node: Node) {
        let declarator = parseDeclarator(node.child(byFieldName: "declarator"))
        let aliasName = lastComponent(of: declarator.name)
        guard !aliasName.isEmpty, let typeNode = node.child(byFieldName: "type") else { return }

        switch typeNode.nodeType {
        case "struct_specifier", "union_specifier", "class_specifier":
            if typeNode.child(byFieldName: "body") != nil {
                if let decl = extractRecord(typeNode, typedefName: aliasName) { types.append(decl) }
                return
            }
        case "enum_specifier":
            if typeNode.child(byFieldName: "body") != nil {
                if let decl = extractEnum(typeNode, typedefName: aliasName) { types.append(decl) }
                return
            }
        default:
            break
        }

        // Plain alias (or alias of a forward-declared/named tag): record a `typeAlias`.
        let underlying = baseTypeReference(typeNode)
        let aliasId = qualifiedName(aliasName)
        types.append(TypeDeclaration(
            id: aliasId, name: aliasName, qualifiedName: aliasId, kind: .typeAlias,
            accessLevel: .public,
            inheritedTypes: underlying.map { [$0] } ?? [],
            namespace: currentNamespace, location: loc(node)
        ))
    }
}
