import UMLCore
import UMLTreeSitter

struct KotlinExtractor {
    private let context: SourceFileContext

    private var types: [TypeDeclaration] = []
    private var relationships: [Relationship] = []
    private var freestandingFunctions: [Member] = []
    private var currentPackage: String?

    init(source: String, fileName: String) {
        self.context = SourceFileContext(source: source, fileName: fileName)
    }

    // MARK: - Public Entry Point

    mutating func extract(from root: Node) -> CodeArtifact {
        walkSourceFile(root)
        resolveRelationshipNames()
        return CodeArtifact(
            metadata: .init(sourceLanguage: .kotlin, filePaths: [context.fileName]),
            types: types,
            relationships: relationships,
            freestandingFunctions: freestandingFunctions
        )
    }

    /// Resolves relationship source/target strings against types discovered in this file.
    ///
    /// During extraction, supertype names are taken verbatim from source text (e.g. `Animal`),
    /// while type IDs are fully qualified (e.g. `com.example.Animal`). This post-processing
    /// step maps short names to qualified IDs so that relationships are immediately matchable
    /// without relying on downstream resolution.
    private mutating func resolveRelationshipNames() {
        var nameToId: [String: String] = [:]
        func register(_ types: [TypeDeclaration]) {
            for type in types {
                nameToId[type.name] = type.id
                nameToId[type.qualifiedName] = type.id
                // For nested types, also register the last component.
                if let simpleName = type.name.components(separatedBy: ".").last,
                   nameToId[simpleName] == nil {
                    nameToId[simpleName] = type.id
                }
                register(type.nestedTypes)
            }
        }
        register(types)

        relationships = relationships.map { rel in
            var resolved = rel
            if let id = nameToId[rel.source] { resolved.source = id }
            if let id = nameToId[rel.target] { resolved.target = id }
            return resolved
        }
    }

    // MARK: - Convenience

    private func text(_ node: Node) -> String { node.text(in: context) }
    private func loc(_ node: Node) -> SourceLocation { node.location(in: context) }
    private func hasKw(_ kw: String, in node: Node) -> Bool { node.hasAnonymousChild(kw, in: context) }

    /// Returns whether the node declares `val` or `var` via a `binding_pattern_kind` child.
    /// Tree-sitter-kotlin wraps `val`/`var` in `[binding_pattern_kind] → [val]`.
    private func bindingKind(of node: Node) -> String? {
        guard let bpk = node.firstChild(withType: "binding_pattern_kind") else { return nil }
        let t = text(bpk).trimmingCharacters(in: .whitespaces)
        return (t == "val" || t == "var") ? t : nil
    }

    private func qualifiedName(_ name: String) -> String {
        currentPackage.map { "\($0).\(name)" } ?? name
    }

    // MARK: - Source File

    private mutating func walkSourceFile(_ node: Node) {
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "package_header":
                currentPackage = child.firstChild(withType: "identifier").map { text($0) }
            case "import_list", "import_header":
                break
            case "class_declaration":
                if child.hasDirectChildText("interface", in: context) {
                    if let t = extractInterfaceDeclaration(child) { types.append(t) }
                } else {
                    if let t = extractClassDeclaration(child) { types.append(t) }
                }
            case "object_declaration":
                if let t = extractObjectDeclaration(child) { types.append(t) }
            case "function_declaration":
                freestandingFunctions.append(extractFunctionDeclaration(child))
            case "type_alias":
                if let t = extractTypeAlias(child) { types.append(t) }
            default:
                break
            }
        }
    }

    // MARK: - Modifiers

    private struct ModifierInfo {
        var accessLevel: AccessLevel
        var modifiers: [Modifier]
        var annotations: [String]
    }

    /// Extracts modifier information from a `modifiers` node.
    ///
    /// In Kotlin every declaration without an explicit visibility modifier is **public**
    /// by default, so the returned `accessLevel` falls back to `.public`.
    private func extractModifiers(_ node: Node?) -> ModifierInfo {
        guard let node, node.nodeType == "modifiers" else {
            return ModifierInfo(accessLevel: .public, modifiers: [], annotations: [])
        }
        var access: AccessLevel?
        var mods: [Modifier] = []
        var annots: [String] = []

        for child in node.namedChildren() {
            let t = text(child)
            switch child.nodeType {
            case "visibility_modifier":
                switch t {
                case "public":    access = .public
                case "private":   access = .private
                case "protected": access = .protected
                case "internal":  access = .internal
                default: break
                }
            case "class_modifier":
                switch t {
                case "data":     mods.append(.data)
                case "sealed":   mods.append(.sealed)
                case "abstract": mods.append(.abstract)
                case "inner":    mods.append(.inner)
                case "value":    mods.append(.inline)
                // "enum" and "annotation" determine TypeKind, not modifiers.
                default: break
                }
            case "member_modifier":
                switch t {
                case "override": mods.append(.override)
                case "lateinit": mods.append(.lazy)
                case "const":    mods.append(.const)
                default: break
                }
            case "property_modifier":
                if t == "const" { mods.append(.const) }
            case "function_modifier":
                switch t {
                case "suspend": mods.append(.suspend)
                case "inline":  mods.append(.inline)
                default: break
                }
            case "inheritance_modifier":
                switch t {
                case "open":     mods.append(.open)
                case "final":    mods.append(.final)
                case "abstract": mods.append(.abstract)
                default: break
                }
            case "annotation":
                let raw = text(child)
                annots.append(raw.hasPrefix("@") ? raw : "@\(raw)")
            default:
                break
            }
        }
        return ModifierInfo(accessLevel: access ?? .public, modifiers: mods, annotations: annots)
    }

    // MARK: - Class Declaration

    private mutating func extractClassDeclaration(_ node: Node) -> TypeDeclaration? {
        let modInfo = extractModifiers(node.firstChild(withType: "modifiers"))

        if node.hasChild(withType: "enum_class_body") {
            return extractEnumClassDeclaration(node, modInfo: modInfo)
        }

        guard let nameNode = node.firstChild(withType: "type_identifier") else { return nil }
        let name = text(nameNode)
        let qn = qualifiedName(name)

        let generics = extractTypeParameters(node.firstChild(withType: "type_parameters"))
        let ctorNode = node.firstChild(withType: "primary_constructor")
        let ctorAccess = ctorNode
            .flatMap { $0.firstChild(withType: "modifiers") }
            .map { extractModifiers($0).accessLevel } ?? modInfo.accessLevel
        let ctorParams = extractPrimaryConstructorParams(ctorNode)
        let supertypes = classifySupertypes(node.allChildren(withType: "delegation_specifier"))

        let isAnnotation = node.firstChild(withType: "modifiers")?.namedChildren()
            .contains { $0.nodeType == "class_modifier" && text($0) == "annotation" } ?? false

        var typeDecl = TypeDeclaration(
            id: qn, name: name, qualifiedName: qn,
            kind: isAnnotation ? .annotation : .class,
            accessLevel: modInfo.accessLevel, modifiers: modInfo.modifiers,
            genericParameters: generics, inheritedTypes: supertypes.map(\.typeRef),
            annotations: modInfo.annotations, namespace: currentPackage, location: loc(node)
        )

        // Promoted constructor properties — each carries its own access level.
        for p in ctorParams where p.isProperty {
            var mods = p.modifiers
            if p.isReadOnly { mods.append(.readonly) }
            typeDecl.members.append(Member(
                name: p.parameter.internalName, kind: .property,
                accessLevel: p.accessLevel, modifiers: mods,
                type: p.parameter.type, annotations: p.annotations
            ))
        }
        if !ctorParams.isEmpty {
            typeDecl.members.append(Member(
                name: "init", kind: .initializer,
                accessLevel: ctorAccess,
                parameters: ctorParams.map(\.parameter)
            ))
        }

        for sup in supertypes {
            relationships.append(Relationship(
                kind: sup.isClassInheritance ? .inheritance : .conformance,
                source: qn, target: sup.typeRef.name))
        }
        if let body = node.firstChild(withType: "class_body") {
            extractBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Interface

    private mutating func extractInterfaceDeclaration(_ node: Node) -> TypeDeclaration? {
        let modInfo = extractModifiers(node.firstChild(withType: "modifiers"))
        guard let nameNode = node.firstChild(withType: "type_identifier") else { return nil }
        let name = text(nameNode)
        let qn = qualifiedName(name)

        let generics = extractTypeParameters(node.firstChild(withType: "type_parameters"))
        let supertypes = classifySupertypes(node.allChildren(withType: "delegation_specifier"))

        var typeDecl = TypeDeclaration(
            id: qn, name: name, qualifiedName: qn, kind: .interface,
            accessLevel: modInfo.accessLevel, modifiers: modInfo.modifiers,
            genericParameters: generics, inheritedTypes: supertypes.map(\.typeRef),
            annotations: modInfo.annotations, namespace: currentPackage, location: loc(node)
        )
        for sup in supertypes {
            relationships.append(Relationship(kind: .conformance, source: qn, target: sup.typeRef.name))
        }
        if let body = node.firstChild(withType: "class_body") {
            extractBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Object Declaration

    private mutating func extractObjectDeclaration(_ node: Node) -> TypeDeclaration? {
        let modInfo = extractModifiers(node.firstChild(withType: "modifiers"))
        guard let nameNode = node.firstChild(withType: "type_identifier") else { return nil }
        let name = text(nameNode)
        let qn = qualifiedName(name)
        let supertypes = classifySupertypes(node.allChildren(withType: "delegation_specifier"))

        var typeDecl = TypeDeclaration(
            id: qn, name: name, qualifiedName: qn, kind: .object,
            accessLevel: modInfo.accessLevel, modifiers: modInfo.modifiers,
            inheritedTypes: supertypes.map(\.typeRef),
            annotations: modInfo.annotations, namespace: currentPackage, location: loc(node)
        )
        for sup in supertypes {
            relationships.append(Relationship(
                kind: sup.isClassInheritance ? .inheritance : .conformance,
                source: qn, target: sup.typeRef.name))
        }
        if let body = node.firstChild(withType: "class_body") {
            extractBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Companion Object

    private mutating func extractCompanionObject(_ node: Node) -> TypeDeclaration? {
        let name = node.firstChild(withType: "type_identifier").map { text($0) } ?? "Companion"
        let qn = qualifiedName(name)
        let supertypes = classifySupertypes(node.allChildren(withType: "delegation_specifier"))

        var typeDecl = TypeDeclaration(
            id: qn, name: name, qualifiedName: qn,
            kind: .object, modifiers: [.static],
            inheritedTypes: supertypes.map(\.typeRef),
            namespace: currentPackage, location: loc(node)
        )
        for sup in supertypes {
            relationships.append(Relationship(
                kind: sup.isClassInheritance ? .inheritance : .conformance,
                source: qn, target: sup.typeRef.name))
        }
        if let body = node.firstChild(withType: "class_body") {
            extractBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Enum Class

    private mutating func extractEnumClassDeclaration(_ node: Node, modInfo: ModifierInfo) -> TypeDeclaration? {
        guard let nameNode = node.firstChild(withType: "type_identifier") else { return nil }
        let name = text(nameNode)
        let qn = qualifiedName(name)

        let generics = extractTypeParameters(node.firstChild(withType: "type_parameters"))
        let supertypes = classifySupertypes(node.allChildren(withType: "delegation_specifier"))

        var typeDecl = TypeDeclaration(
            id: qn, name: name, qualifiedName: qn, kind: .enum,
            accessLevel: modInfo.accessLevel, modifiers: modInfo.modifiers,
            genericParameters: generics, inheritedTypes: supertypes.map(\.typeRef),
            annotations: modInfo.annotations, namespace: currentPackage, location: loc(node)
        )
        for sup in supertypes {
            relationships.append(Relationship(
                kind: sup.isClassInheritance ? .inheritance : .conformance,
                source: qn, target: sup.typeRef.name))
        }
        if let body = node.firstChild(withType: "enum_class_body") {
            for child in body.namedChildren() where child.nodeType == "enum_entry" {
                if let ec = extractEnumEntry(child) { typeDecl.enumCases.append(ec) }
            }
            extractBody(body, into: &typeDecl, skipEnumEntries: true)
        } else if let body = node.firstChild(withType: "class_body") {
            extractBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Type Alias

    private func extractTypeAlias(_ node: Node) -> TypeDeclaration? {
        guard let nameNode = node.firstChild(withType: "type_identifier") else { return nil }
        let name = text(nameNode)
        let qn = qualifiedName(name)
        let modInfo = extractModifiers(node.firstChild(withType: "modifiers"))
        let generics = extractTypeParameters(node.firstChild(withType: "type_parameters"))

        var targetType: [TypeReference] = []
        if let ut = node.firstChild(withType: "user_type") { targetType.append(extractTypeReference(ut)) }
        else if let nt = node.firstChild(withType: "nullable_type") { targetType.append(extractNullableType(nt)) }

        return TypeDeclaration(
            id: qn, name: name, qualifiedName: qn, kind: .typeAlias,
            accessLevel: modInfo.accessLevel, genericParameters: generics,
            inheritedTypes: targetType, annotations: modInfo.annotations,
            namespace: currentPackage, location: loc(node)
        )
    }

    // MARK: - Body Extraction

    /// Extracts members, nested types, and companion objects from a class/interface/object body.
    /// Used for both `class_body` and `enum_class_body` nodes.
    private mutating func extractBody(
        _ node: Node,
        into typeDecl: inout TypeDeclaration,
        skipEnumEntries: Bool = false
    ) {
        // Pre-scan: build property → type map for call-site resolution.
        var knownProperties: [String: String] = [:]
        for member in typeDecl.members where member.kind == .property {
            if let typeName = member.type?.name { knownProperties[member.name] = typeName }
        }
        for child in node.namedChildren() where child.nodeType == "property_declaration" {
            let prop = extractPropertyDeclaration(child)
            if !prop.modifiers.contains(.static), let typeName = prop.type?.name {
                knownProperties[prop.name] = typeName
            }
        }

        let namedChildren = node.namedChildren()
        for (idx, child) in namedChildren.enumerated() {
            switch child.nodeType {
            case "enum_entry" where skipEnumEntries:
                continue
            case "function_declaration":
                typeDecl.members.append(extractFunctionDeclaration(child, knownProperties: knownProperties))
            case "property_declaration":
                // In tree-sitter-kotlin, getter/setter nodes are siblings of the
                // property_declaration, not children. Look ahead to detect them.
                let hasGetterOrSetter: Bool = {
                    let next = idx + 1
                    guard next < namedChildren.count else { return false }
                    let sibling = namedChildren[next].nodeType
                    return sibling == "getter" || sibling == "setter"
                }()
                typeDecl.members.append(extractPropertyDeclaration(child, isComputed: hasGetterOrSetter))
            case "secondary_constructor":
                typeDecl.members.append(extractSecondaryConstructor(child, knownProperties: knownProperties))
            case "companion_object":
                if let obj = extractCompanionObject(child) { typeDecl.nestedTypes.append(obj) }
            case "class_declaration":
                if child.hasDirectChildText("interface", in: context) {
                    if let n = extractInterfaceDeclaration(child) { typeDecl.nestedTypes.append(n) }
                } else if let n = extractClassDeclaration(child) {
                    typeDecl.nestedTypes.append(n)
                }
            case "object_declaration":
                if let n = extractObjectDeclaration(child) { typeDecl.nestedTypes.append(n) }
            default:
                break
            }
        }
    }

    // MARK: - Enum Entry

    private func extractEnumEntry(_ node: Node) -> EnumCase? {
        guard let nameNode = node.firstChild(withType: "simple_identifier") else { return nil }
        let name = text(nameNode)
        var rawValue: String?
        if let valueArgs = node.firstChild(withType: "value_arguments") {
            let t = text(valueArgs).trimmingCharacters(in: .whitespaces)
            rawValue = (t.hasPrefix("(") && t.hasSuffix(")")) ? String(t.dropFirst().dropLast()) : t
        }
        return EnumCase(name: name, rawValue: rawValue, location: loc(node))
    }

    // MARK: - Function Declaration

    private mutating func extractFunctionDeclaration(
        _ node: Node,
        knownProperties: [String: String] = [:]
    ) -> Member {
        let modInfo = extractModifiers(node.firstChild(withType: "modifiers"))
        let name = node.firstChild(withType: "simple_identifier").map { text($0) } ?? "_anonymous"
        let generics = extractTypeParameters(node.firstChild(withType: "type_parameters"))

        // Extension function receiver (e.g. `fun String.hello() {}`)
        if let receiverRef = extractReceiverType(node) {
            relationships.append(Relationship(kind: .extension, source: name, target: receiverRef.name))
        }

        let params = extractFunctionValueParameters(node.firstChild(withType: "function_value_parameters"))
        let returnType: TypeReference? = {
            guard let rt = findReturnType(in: node) else { return nil }
            let ref = extractTypeReferenceFromAny(rt)
            return ref.name == "Unit" ? nil : ref
        }()

        let callSites = extractCallSites(from: node.firstChild(withType: "function_body"),
                                         knownProperties: knownProperties)

        return Member(
            name: name, kind: .method,
            accessLevel: modInfo.accessLevel, modifiers: modInfo.modifiers,
            type: returnType, parameters: params,
            genericParameters: generics, annotations: modInfo.annotations, location: loc(node),
            callSites: callSites
        )
    }

    /// Extracts the receiver type from a Kotlin extension function declaration.
    ///
    /// In `fun String.hello() {}`, `String` is the receiver type. The tree-sitter
    /// AST places this as a type node child followed by a `"."` anonymous child
    /// before the function name.
    private func extractReceiverType(_ node: Node) -> TypeReference? {
        let children = node.children()
        guard let funIdx = children.firstIndex(where: { !$0.isNamed && text($0) == "fun" }) else { return nil }
        var i = children.index(after: funIdx)
        while i < children.endIndex {
            let child = children[i]
            // Skip type parameters (generics before receiver)
            if child.nodeType == "type_parameters" { i = children.index(after: i); continue }
            // A type node followed by "." indicates a receiver type.
            if child.isNamed,
               let nodeType = child.nodeType,
               ["user_type", "nullable_type", "parenthesized_type"].contains(nodeType) {
                let nextIdx = children.index(after: i)
                if nextIdx < children.endIndex,
                   !children[nextIdx].isNamed,
                   text(children[nextIdx]) == "." {
                    return extractTypeReferenceFromAny(child)
                }
            }
            break // Not an extension function
        }
        return nil
    }

    private func findReturnType(in node: Node) -> Node? {
        var foundParams = false
        var foundColon = false
        for child in node.children() {
            let ct = child.nodeType
            if ct == "function_value_parameters" { foundParams = true; continue }
            if foundParams && !child.isNamed && text(child) == ":" { foundColon = true; continue }
            if foundColon && child.isNamed {
                if ["user_type", "nullable_type", "function_type", "parenthesized_type"].contains(ct) { return child }
                break
            }
            if ct == "function_body" { break }
        }
        return nil
    }

    // MARK: - Property Declaration

    private func extractPropertyDeclaration(_ node: Node, isComputed: Bool = false) -> Member {
        let modInfo = extractModifiers(node.firstChild(withType: "modifiers"))
        let isVal = bindingKind(of: node) == "val"
        var mods = modInfo.modifiers
        if isVal { mods.append(.readonly) }

        var name = ""
        var typeRef: TypeReference?

        if let varDecl = node.firstChild(withType: "variable_declaration") {
            name = varDecl.firstChild(withType: "simple_identifier").map { text($0) } ?? ""
            typeRef = extractFirstTypeRef(from: varDecl)
        } else {
            name = node.firstChild(withType: "simple_identifier").map { text($0) } ?? ""
            typeRef = extractFirstTypeRef(from: node)
        }

        return Member(
            name: name, kind: .property,
            accessLevel: modInfo.accessLevel, modifiers: mods,
            type: typeRef,
            isComputed: isComputed,
            annotations: modInfo.annotations, location: loc(node)
        )
    }

    private func extractFirstTypeRef(from node: Node) -> TypeReference? {
        for child in node.namedChildren() {
            switch child.nodeType {
            case "user_type":     return extractTypeReference(child)
            case "nullable_type": return extractNullableType(child)
            case "function_type": return extractFunctionType(child)
            default: break
            }
        }
        return nil
    }

    // MARK: - Secondary Constructor

    private func extractSecondaryConstructor(
        _ node: Node,
        knownProperties: [String: String] = [:]
    ) -> Member {
        let modInfo = extractModifiers(node.firstChild(withType: "modifiers"))
        let params = extractFunctionValueParameters(node.firstChild(withType: "function_value_parameters"))
        let callSites = extractCallSites(from: node.firstChild(withType: "block"),
                                         knownProperties: knownProperties)
        return Member(name: "init", kind: .initializer, accessLevel: modInfo.accessLevel,
                      parameters: params, location: loc(node), callSites: callSites)
    }

    // MARK: - Primary Constructor Parameters

    private struct ClassParam {
        let parameter: Parameter
        let isProperty: Bool
        let isReadOnly: Bool
        let accessLevel: AccessLevel
        let modifiers: [Modifier]
        let annotations: [String]
    }

    private func extractPrimaryConstructorParams(_ node: Node?) -> [ClassParam] {
        guard let node else { return [] }
        let classParamsNode = node.firstChild(withType: "class_parameters") ?? node
        return classParamsNode.allChildren(withType: "class_parameter").map { child in
            let paramModInfo = extractModifiers(child.firstChild(withType: "modifiers"))
            let bk = bindingKind(of: child)
            let isVal = bk == "val"
            let isVar = bk == "var"
            let isProperty = isVal || isVar
            let name = child.firstChild(withType: "simple_identifier").map { text($0) } ?? ""
            let typeRef = extractFirstTypeRef(from: child)
            var defaultValue: String?
            var foundEq = false
            for c in child.children() {
                if !c.isNamed && text(c) == "=" { foundEq = true; continue }
                if foundEq && c.isNamed { defaultValue = text(c); break }
            }
            return ClassParam(
                parameter: Parameter(internalName: name, type: typeRef, defaultValue: defaultValue),
                isProperty: isProperty,
                isReadOnly: isVal,
                accessLevel: paramModInfo.accessLevel,
                modifiers: paramModInfo.modifiers,
                annotations: paramModInfo.annotations
            )
        }
    }

    // MARK: - Function Value Parameters

    private func extractFunctionValueParameters(_ node: Node?) -> [Parameter] {
        guard let node else { return [] }
        return node.allChildren(withType: "parameter").map { child in
            let name = child.firstChild(withType: "simple_identifier").map { text($0) } ?? ""
            let typeRef = extractFirstTypeRef(from: child)
            var defaultValue: String?
            var foundEq = false
            for c in child.children() {
                if !c.isNamed && text(c) == "=" { foundEq = true; continue }
                if foundEq && c.isNamed { defaultValue = text(c); break }
            }
            return Parameter(
                internalName: name, type: typeRef,
                defaultValue: defaultValue,
                isVariadic: hasKw("vararg", in: child)
            )
        }
    }

    // MARK: - Supertype Classification

    /// A type reference paired with whether it came from a constructor invocation
    /// (class inheritance) or a bare type / delegation (interface conformance).
    private struct ClassifiedSupertype {
        let typeRef: TypeReference
        let isClassInheritance: Bool
    }

    private func classifySupertypes(_ specifiers: [Node]) -> [ClassifiedSupertype] {
        specifiers.compactMap { specifier in
            if let ctorInv = specifier.firstChild(withType: "constructor_invocation"),
               let ut = ctorInv.firstChild(withType: "user_type") {
                return ClassifiedSupertype(typeRef: extractTypeReference(ut), isClassInheritance: true)
            } else if let ut = specifier.firstChild(withType: "user_type") {
                return ClassifiedSupertype(typeRef: extractTypeReference(ut), isClassInheritance: false)
            } else if let expDel = specifier.firstChild(withType: "explicit_delegation"),
                      let ut = expDel.firstChild(withType: "user_type") {
                return ClassifiedSupertype(typeRef: extractTypeReference(ut), isClassInheritance: false)
            }
            return nil
        }
    }

    // MARK: - Type References

    private func extractTypeReferenceFromAny(_ node: Node) -> TypeReference {
        switch node.nodeType {
        case "user_type":     return extractTypeReference(node)
        case "nullable_type": return extractNullableType(node)
        case "function_type": return extractFunctionType(node)
        case "parenthesized_type":
            return node.namedChildren().first.map { extractTypeReferenceFromAny($0) }
                ?? TypeReference(name: text(node))
        default:
            return TypeReference(name: text(node))
        }
    }

    private func extractTypeReference(_ node: Node) -> TypeReference {
        var nameParts: [String] = []
        var genericArgs: [TypeReference] = []
        for child in node.namedChildren() {
            switch child.nodeType {
            case "type_identifier": nameParts.append(text(child))
            case "type_arguments":  genericArgs = extractTypeArguments(child)
            default: break
            }
        }
        return TypeReference(name: nameParts.joined(separator: "."), genericArguments: genericArgs)
    }

    private func extractNullableType(_ node: Node) -> TypeReference {
        if let inner = node.namedChildren().first {
            var ref = extractTypeReferenceFromAny(inner)
            ref.isOptional = true
            return ref
        }
        var t = text(node)
        if t.hasSuffix("?") { t = String(t.dropLast()) }
        return TypeReference(name: t, isOptional: true)
    }

    private func extractFunctionType(_ node: Node) -> TypeReference { TypeReference(name: text(node)) }

    private func extractTypeArguments(_ node: Node) -> [TypeReference] {
        node.namedChildren().compactMap { child in
            switch child.nodeType {
            case "type_projection":
                if let star = child.firstChild(withType: "star_projection") { return TypeReference(name: text(star)) }
                return child.namedChildren().first.map { extractTypeReferenceFromAny($0) }
            case "user_type":     return extractTypeReference(child)
            case "nullable_type": return extractNullableType(child)
            default:              return nil
            }
        }
    }

    // MARK: - Call Site Extraction

    /// Recursively walks `body` collecting every resolvable `receiver.method()` call.
    private func extractCallSites(from body: Node?, knownProperties: [String: String]) -> [CallSite] {
        guard let body, !knownProperties.isEmpty else { return [] }
        var sites: [CallSite] = []
        walkForCallSites(body, knownProperties: knownProperties, into: &sites)
        return sites
    }

    private func walkForCallSites(_ node: Node, knownProperties: [String: String], into sites: inout [CallSite]) {
        if let site = resolveCallSite(node, knownProperties: knownProperties) {
            sites.append(site)
        }
        for child in node.namedChildren() {
            walkForCallSites(child, knownProperties: knownProperties, into: &sites)
        }
    }

    /// Resolves `receiver.method(args)` and `this.receiver.method(args)` call patterns.
    private func resolveCallSite(_ node: Node, knownProperties: [String: String]) -> CallSite? {
        guard node.nodeType == "call_expression",
              let navExpr = node.firstChild(withType: "navigation_expression")
        else { return nil }

        // Method name lives in the last navigation_suffix → simple_identifier
        guard let navSuffix = navExpr.firstChild(withType: "navigation_suffix"),
              let methodNode = navSuffix.firstChild(withType: "simple_identifier")
        else { return nil }
        let methodName = text(methodNode)

        // Resolve receiver variable name
        var receiverVarName: String? = nil

        if let firstId = navExpr.firstChild(withType: "simple_identifier") {
            // Pattern: receiverVar.method(args)
            receiverVarName = text(firstId)
        } else if let innerNav = navExpr.firstChild(withType: "navigation_expression"),
                  innerNav.firstChild(withType: "this_expression") != nil,
                  let innerSuffix = innerNav.firstChild(withType: "navigation_suffix"),
                  let propId = innerSuffix.firstChild(withType: "simple_identifier") {
            // Pattern: this.receiverVar.method(args)
            receiverVarName = text(propId)
        }

        guard let varName = receiverVarName,
              let receiverType = knownProperties[varName]
        else { return nil }

        return CallSite(receiverType: receiverType, methodName: methodName, location: loc(node))
    }

    // MARK: - Generic Parameters

    private func extractTypeParameters(_ node: Node?) -> [GenericParameter] {
        guard let node else { return [] }
        return node.allChildren(withType: "type_parameter").compactMap { child in
            let name = child.firstChild(withType: "type_identifier").map { text($0) }
                ?? child.firstChild(withType: "simple_identifier").map { text($0) }
                ?? ""
            guard !name.isEmpty else { return nil }
            var constraints: [GenericConstraint] = []
            if let ut = child.firstChild(withType: "user_type") {
                constraints.append(GenericConstraint(kind: .conformance, type: extractTypeReference(ut)))
            } else if let nt = child.firstChild(withType: "nullable_type") {
                constraints.append(GenericConstraint(kind: .conformance, type: extractNullableType(nt)))
            }
            return GenericParameter(name: name, constraints: constraints)
        }
    }
}
