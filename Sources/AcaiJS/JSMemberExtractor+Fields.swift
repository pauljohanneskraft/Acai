import AcaiCore
import AcaiTreeSitter

// MARK: - Fields & Class-Body Pre-Pass Maps

extension JSMemberExtractor {

    // MARK: - Class Body Pre-Pass Maps

    /// The class body's direct stored properties as the scope needs them: `types` is
    /// `fieldName → typeName` so a same-type method call through a typed stored property
    /// (`this.cache.process()`) resolves, and `names` is every non-static property name, typed or
    /// not. The two differ in JavaScript, where no field carries a type: field-read capture filters
    /// by name alone, so giving it only the typed subset loses every read in the language. Built
    /// before member extraction, so it can't itself depend on the scope it feeds.
    func propertyIndex(fromBody bodyNode: Node) -> (types: [String: String], names: Set<String>) {
        var properties: [Member] = []
        for child in bodyNode.children() {
            guard let childType = child.nodeType else { continue }

            if childType == "field_definition" || childType == "public_field_definition" {
                properties.append(fieldDefinition(child, references: ValueReferences()))
            } else if childType == "method_definition", isTypeScript,
                      child.child(byFieldName: "name").map({ $0.text(in: context) }) == "constructor" {
                properties.append(contentsOf: constructorParameterProperties(child))
            }
        }

        var types: [String: String] = [:]
        var names: Set<String> = []
        for property in properties where !property.modifiers.contains(.static) && !property.name.isEmpty {
            names.insert(property.name)
            if let typeName = property.type?.name { types[property.name] = typeName }
        }
        return (types, names)
    }

    /// A `methodName → returnTypeName` map from the class body's direct `method_definition` children
    /// (TypeScript only — JS has no return-type annotations), so a same-type method call with an
    /// unambiguous return type can seed a local's type. Overloaded names with differing return types
    /// are dropped rather than guessed.
    func methodReturnTypeMap(fromBody bodyNode: Node) -> [String: String] {
        guard isTypeScript else { return [:] }
        var returnTypes = UnambiguousTypeNames()
        for child in bodyNode.children() where child.nodeType == "method_definition" {
            guard let nameNode = child.child(byFieldName: "name"),
                  let returnType = typeReferences.extractReturnTypeAnnotation(child)
            else { continue }
            returnTypes.record(returnType.name, for: nameNode.text(in: context))
        }
        return returnTypes.resolved
    }

    // MARK: - Field Definition

    func fieldDefinition(_ node: Node, references: ValueReferences) -> Member {
        let nameNode = node.child(byFieldName: "property") ?? node.child(byFieldName: "name")
        let name = nameNode.map { $0.text(in: context) } ?? ""

        var accessLevel: AccessLevel? = name.hasPrefix("#") ? .private : nil
        if isTypeScript, let acc = typeReferences.extractAccessibilityModifier(node) {
            accessLevel = acc
        }

        var propType = isTypeScript ? typeReferences.extractTypeAnnotation(node) : nil
        // No (or no TypeScript) annotation — infer from a direct construction initializer (`private
        // cache = new ImageCache();`), same heuristic `localBindings` applies to locals. Without
        // this, calls through a composed collaborator field (`this.cache.process()`) can't resolve.
        if propType == nil {
            propType = constructedType(fromFieldValue: node.child(byFieldName: "value"))
        }
        if node.hasDirectChildText("?", in: context) {
            propType?.isOptional = true
        }

        return Member(
            name: name.isEmpty ? "_unknown" : name,
            kind: .property,
            accessLevel: accessLevel ?? .public,
            modifiers: fieldModifiers(node),
            type: propType,
            annotations: decorators(node),
            location: node.location(in: context),
            callSites: references.callSites,
            initialValue: references.initialValue,
            referencedTypeNames: references.referencedTypeNames
        )
    }

    /// The type a field or global variable's `new Foo()` initializer proves, absent a TypeScript
    /// annotation. Mirrors the construction check `JSCallSiteSyntax.localBindings` applies to locals.
    func constructedType(fromFieldValue value: Node?) -> TypeReference? {
        guard let value, value.nodeType == "new_expression",
              let ctor = value.child(byFieldName: "constructor"), ctor.nodeType == "identifier"
        else { return nil }
        return TypeReference(name: ctor.text(in: context))
    }

    private func fieldModifiers(_ node: Node) -> [Modifier] {
        var modifiers: [Modifier] = []
        if node.hasDirectChildText("static", in: context) { modifiers.append(.static) }
        guard isTypeScript else { return modifiers }
        if node.hasDirectChildText("readonly", in: context) { modifiers.append(.readonly) }
        if node.hasDirectChildText("abstract", in: context) { modifiers.append(.abstract) }
        if node.hasDirectChildText("override", in: context) { modifiers.append(.override) }
        if node.hasDirectChildText("declare", in: context) { modifiers.append(.declare) }
        return modifiers
    }

    // MARK: - Top-Level Variable Declaration

    /// A top-level (module-scope) `const`/`let`/`var` declarator, or one inside a TS `namespace`
    /// body. Reuses the same type-inference and value-classification `fieldDefinition` applies to a
    /// class field, since JS/TS has no separate grammar node for global vs. instance state.
    func globalVariable(_ node: Node, name: String, isExported: Bool, references: ValueReferences) -> Member {
        let value = node.child(byFieldName: "value")

        var propType = isTypeScript ? typeReferences.extractTypeAnnotation(node) : nil
        if propType == nil {
            propType = constructedType(fromFieldValue: value)
        }

        return Member(
            name: name,
            kind: .property,
            accessLevel: isExported ? .public : .internal,
            type: propType,
            location: node.location(in: context),
            callSites: references.callSites,
            initialValue: references.initialValue,
            referencedTypeNames: references.referencedTypeNames
        )
    }
}
