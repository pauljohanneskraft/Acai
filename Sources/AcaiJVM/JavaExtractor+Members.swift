import AcaiCore
import AcaiTreeSitter

// MARK: - Body & Member Extraction

extension JavaExtractor {

    private static let fieldNodeTypes: Set<String> = ["field_declaration", "constant_declaration"]

    /// An enum keeps its methods and fields in an `enum_body_declarations` child rather than directly
    /// under its body, so the two scope pre-passes below look through it.
    private func declarationChildren(ofBody node: Node) -> [Node] {
        let children = node.children()
        guard let nested = children.first(where: { $0.nodeType == "enum_body_declarations" }) else {
            return children
        }
        return children + nested.children()
    }

    /// `fieldName → typeName` from the type's own members plus its declared fields, so a same-type
    /// method call through a typed stored property (`this.cache.process()`) resolves. An interface
    /// spells its fields `constant_declaration`. `existingMembers` lets a record's already-collected
    /// component properties count too.
    private func propertyMap(existingMembers: [Member], fromBody node: Node) -> [String: String] {
        var knownProperties: [String: String] = [:]
        for member in existingMembers where member.kind == .property {
            if let typeName = member.type?.name { knownProperties[member.name] = typeName }
        }
        for child in declarationChildren(ofBody: node) {
            guard let nodeType = child.nodeType, Self.fieldNodeTypes.contains(nodeType) else { continue }
            for field in fieldMembers(from: child, scope: nil) where field.kind == .property {
                if let typeName = field.type?.name { knownProperties[field.name] = typeName }
            }
        }
        return knownProperties
    }

    /// A `methodName → returnTypeName` map from the type's own method declarations (a one-level
    /// pre-pass, mirroring `propertyMap` above), so a same-type method call with an unambiguous
    /// return type can seed a local's type. Overloaded names with differing return types are dropped.
    private func methodReturnTypeMap(fromBody node: Node) -> [String: String] {
        var typesByName: [String: Set<String>] = [:]
        for child in declarationChildren(ofBody: node) where child.nodeType == "method_declaration" {
            guard let nameNode = child.child(byFieldName: "name"),
                  let typeNode = child.child(byFieldName: "type"),
                  let typeName = typeReferences.extractTypeReference(typeNode)?.name
            else { continue }
            typesByName[nameNode.text(in: context), default: []].insert(typeName)
        }
        return typesByName.compactMapValues { $0.count == 1 ? $0.first : nil }
    }

    mutating func extractNestedTypeFromChild(
        _ child: Node,
        nodeType: String,
        parentQualifiedName: String
    ) -> TypeDeclaration? {
        // Parent type's qualified name as namespace, so nested types get correct IDs.
        let outer = declarations.enter(namespace: parentQualifiedName)
        defer { declarations.leave(outer) }

        switch nodeType {
        case "class_declaration":
            return extractClassDeclaration(child)
        case "interface_declaration":
            return extractInterfaceDeclaration(child)
        case "enum_declaration":
            return extractEnumDeclaration(child)
        case "record_declaration":
            return extractRecordDeclaration(child)
        case "annotation_type_declaration":
            return extractAnnotationTypeDeclaration(child)
        default:
            return nil
        }
    }

    // MARK: - Unified Body Dispatch

    private enum BodyChildRole {
        case method
        case constructor
        case field
        case initializerBlock
        case nestedType
        case enumConstant
        case enumBodyDeclarations
        case annotationTypeElement
    }

    private static let classBodyDispatch: [String: BodyChildRole] = [
        "method_declaration": .method,
        "constructor_declaration": .constructor,
        "field_declaration": .field,
        "static_initializer": .initializerBlock,
        "block": .initializerBlock,
        "class_declaration": .nestedType,
        "interface_declaration": .nestedType,
        "enum_declaration": .nestedType,
        "record_declaration": .nestedType,
        "annotation_type_declaration": .nestedType
    ]

    private static let interfaceBodyDispatch: [String: BodyChildRole] = [
        "method_declaration": .method,
        "constant_declaration": .field,
        "field_declaration": .field,
        "class_declaration": .nestedType,
        "interface_declaration": .nestedType,
        "enum_declaration": .nestedType,
        "record_declaration": .nestedType,
        "annotation_type_declaration": .nestedType
    ]

    private static let enumBodyDispatch: [String: BodyChildRole] = [
        "enum_constant": .enumConstant,
        "enum_body_declarations": .enumBodyDeclarations,
        "method_declaration": .method,
        "constructor_declaration": .constructor,
        "field_declaration": .field,
        "static_initializer": .initializerBlock,
        "block": .initializerBlock,
        "class_declaration": .nestedType,
        "interface_declaration": .nestedType
    ]

    private static let annotationTypeBodyDispatch: [String: BodyChildRole] = [
        "annotation_type_element_declaration": .annotationTypeElement,
        "field_declaration": .field,
        "constant_declaration": .field,
        "class_declaration": .nestedType,
        "interface_declaration": .nestedType,
        "enum_declaration": .nestedType
    ]

    private func appendIfPresent<T>(_ value: T?, to array: inout [T]) {
        if let value { array.append(value) }
    }

    struct BodyExtractionContext {
        var members: [Member] = []
        var nestedTypes: [TypeDeclaration] = []
        var enumCases: [EnumCase] = []
        let parentQualifiedName: String
        var scope: CallSiteScope = CallSiteScope()
        var memberDefaults: JavaMemberDefaults = .classBody
    }

    private mutating func extractBodyMembers(
        _ node: Node,
        context: inout BodyExtractionContext,
        dispatch: [String: BodyChildRole]
    ) {
        for (child, role) in NodeDispatch(dispatch).matches(in: node) {
            guard let nodeType = child.nodeType else { continue }
            dispatchBodyChild(role, child: child, nodeType: nodeType, context: &context)
        }
    }

    private mutating func dispatchBodyChild(
        _ role: BodyChildRole,
        child: Node,
        nodeType: String,
        context: inout BodyExtractionContext
    ) {
        let before = (
            members: context.members.count,
            nestedTypes: context.nestedTypes.count,
            enumCases: context.enumCases.count
        )
        appendBodyChild(role, child: child, nodeType: nodeType, context: &context)
        guard context.members.count > before.members || context.nestedTypes.count > before.nestedTypes
            || context.enumCases.count > before.enumCases,
            let prose = documentation.documentation(above: child, in: self.context) else { return }
        for index in before.members..<context.members.count {
            context.members[index].documentation = prose
        }
        for index in before.nestedTypes..<context.nestedTypes.count {
            context.nestedTypes[index].documentation = prose
        }
        for index in before.enumCases..<context.enumCases.count {
            context.enumCases[index].documentation = prose
        }
    }

    private mutating func appendBodyChild(
        _ role: BodyChildRole,
        child: Node,
        nodeType: String,
        context: inout BodyExtractionContext
    ) {
        switch role {
        case .method:
            appendIfPresent(
                extractMethodDeclaration(child, scope: context.scope, defaults: context.memberDefaults),
                to: &context.members
            )
        case .constructor:
            context.members.append(extractConstructorDeclaration(child, scope: context.scope))
        case .field:
            context.members.append(
                contentsOf: fieldMembers(from: child, scope: context.scope, defaults: context.memberDefaults)
            )
        case .initializerBlock:
            // A `static { … }` / instance `{ … }` initializer block. Its calls run during
            // construction, so record them on an `.initializer` member, never a dead-code candidate.
            context.members.append(
                Member(
                    name: "init", kind: .initializer, accessLevel: .internal,
                    location: child.location(in: self.context),
                    callSites: callSites.callSites(in: child, scope: context.scope)
                )
            )
        case .nestedType:
            appendIfPresent(
                extractNestedTypeFromChild(
                    child, nodeType: nodeType,
                    parentQualifiedName: context.parentQualifiedName
                ),
                to: &context.nestedTypes
            )
        case .enumConstant:
            appendIfPresent(extractEnumConstant(child), to: &context.enumCases)
        case .enumBodyDeclarations:
            extractClassBody(child, context: &context)
        case .annotationTypeElement:
            appendIfPresent(
                extractAnnotationTypeElement(child, defaults: context.memberDefaults),
                to: &context.members
            )
        }
    }

    // MARK: - Body Extraction Wrappers

    mutating func extractClassBody(
        _ node: Node,
        context: inout BodyExtractionContext
    ) {
        extractBody(node, context: &context, dispatch: Self.classBodyDispatch, defaults: .classBody)
    }

    mutating func extractInterfaceBody(
        _ node: Node,
        context: inout BodyExtractionContext
    ) {
        extractBody(node, context: &context, dispatch: Self.interfaceBodyDispatch, defaults: .interfaceBody)
    }

    mutating func extractEnumBody(
        _ node: Node,
        context: inout BodyExtractionContext
    ) {
        extractBody(node, context: &context, dispatch: Self.enumBodyDispatch, defaults: .classBody)
    }

    mutating func extractAnnotationTypeBody(
        _ node: Node,
        context: inout BodyExtractionContext
    ) {
        extractBody(
            node, context: &context, dispatch: Self.annotationTypeBodyDispatch, defaults: .interfaceBody
        )
    }

    /// Every body resolves its calls against the same scope — the type's own properties, the file's
    /// declared type names and its unambiguous method return types — and tells its members which
    /// modifiers the enclosing body implies.
    private mutating func extractBody(
        _ node: Node,
        context: inout BodyExtractionContext,
        dispatch: [String: BodyChildRole],
        defaults: JavaMemberDefaults
    ) {
        context.scope = CallSiteScope(
            knownProperties: propertyMap(existingMembers: context.members, fromBody: node),
            knownTypeNames: declarations.declaredTypeNames,
            knownMethodReturnTypes: methodReturnTypeMap(fromBody: node)
        )
        context.memberDefaults = defaults
        extractBodyMembers(node, context: &context, dispatch: dispatch)
    }

    private func extractAnnotationTypeElement(_ node: Node, defaults: JavaMemberDefaults) -> Member? {
        let modifierInfo = defaults.method(modifiers.info(fromParentOf: node), hasBody: false)
        let returnType = node.child(byFieldName: "type").flatMap { typeReferences.extractTypeReference($0) }
        return memberExtractor.annotationTypeElement(node, modifierInfo: modifierInfo, returnType: returnType)
    }

    // MARK: - Enum Constant

    private func extractEnumConstant(_ node: Node) -> EnumCase? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = nameNode.text(in: context)
        guard !name.isEmpty else { return nil }
        let nodeLoc = node.location(in: context)

        var arguments: [Parameter] = []
        if let argsNode = node.child(byFieldName: "arguments") {
            arguments = parameterExtractor.argumentsAsParameters(argsNode)
        }

        return EnumCase(name: name, associatedValues: arguments, location: nodeLoc)
    }

    // MARK: - Method Declaration

    func extractMethodDeclaration(
        _ node: Node,
        scope: CallSiteScope = CallSiteScope(),
        defaults: JavaMemberDefaults
    ) -> Member? {
        let body = node.child(byFieldName: "body")
        let modifierInfo = defaults.method(modifiers.info(fromParentOf: node), hasBody: body != nil)
        let returnType = node.child(byFieldName: "type").flatMap { typeReferences.extractTypeReference($0) }
        let generics = typeReferences.extractTypeParameters(from: node)
        let parameters = node.child(byFieldName: "parameters").map { parameterExtractor.parameters($0) } ?? []

        let mergedScope = scope.merging(parameters: parameters)

        return memberExtractor.methodDeclaration(
            node,
            signature: .init(
                modifierInfo: modifierInfo, generics: generics, parameters: parameters, returnType: returnType),
            references: .init(
                callSites: callSites.callSites(in: body, scope: mergedScope),
                assignments: assignments.assignments(in: body),
                fieldReads: fieldReads.reads(in: body, scope: scope),
                referencedTypeNames: body?.referencedTypeNames(in: context) ?? [],
                cyclomaticComplexity: body?.cyclomaticComplexity(
                    branchKinds: Self.branchNodeKinds, fallbackMarkers: Self.complexityFallbackMarkers)
            )
        )
    }

    // MARK: - Constructor Declaration

    func extractConstructorDeclaration(
        _ node: Node,
        scope: CallSiteScope = CallSiteScope()
    ) -> Member {
        let modifierInfo = modifiers.info(fromParentOf: node)
        let generics = typeReferences.extractTypeParameters(from: node)
        let parameters = node.child(byFieldName: "parameters").map { parameterExtractor.parameters($0) } ?? []

        let body = node.child(byFieldName: "body")
        let mergedScope = scope.merging(parameters: parameters)

        return memberExtractor.constructorDeclaration(
            node,
            signature: .init(modifierInfo: modifierInfo, generics: generics, parameters: parameters),
            references: .init(
                callSites: callSites.callSites(in: body, scope: mergedScope),
                assignments: assignments.assignments(in: body),
                fieldReads: fieldReads.reads(in: body, scope: scope),
                referencedTypeNames: body?.referencedTypeNames(in: context) ?? [],
                cyclomaticComplexity: body?.cyclomaticComplexity(
                    branchKinds: Self.branchNodeKinds, fallbackMarkers: Self.complexityFallbackMarkers)
            )
        )
    }

    // MARK: - Field Declaration

    /// `scope` is `nil` for the type-body pre-pass (only each field's type is read; references are
    /// left empty rather than resolving real call sites against a scope that isn't ready yet).
    private func fieldMembers(
        from node: Node, scope: CallSiteScope?, defaults: JavaMemberDefaults = .classBody
    ) -> [Member] {
        let modifierInfo = defaults.field(modifiers.info(fromParentOf: node))
        let nodeLoc = node.location(in: context)
        let fieldType = node.child(byFieldName: "type").flatMap { typeReferences.extractTypeReference($0) }

        // Collect all variable_declarator children (handles: int x, y, z;)
        let declarators = node.allChildren(withType: "variable_declarator")
        let declaratorNodes = declarators.isEmpty
            ? node.child(byFieldName: "declarator").map { [$0] } ?? [] // Fallback: try declarator field name
            : declarators

        return declaratorNodes.compactMap { declarator in
            memberExtractor.fieldMember(
                declarator, fieldType: fieldType, modifierInfo: modifierInfo, location: nodeLoc,
                references: scope.map { fieldValueReferences(for: declarator, scope: $0) } ?? .init()
            )
        }
    }

    private func fieldValueReferences(
        for declarator: Node, scope: CallSiteScope
    ) -> JavaMemberExtractor.ValueReferences {
        let value = declarator.child(byFieldName: "value")
        return .init(
            callSites: callSites.callSites(in: value, scope: scope),
            initialValue: value.map { assignmentSyntax.classifyValue($0) },
            referencedTypeNames: value?.referencedTypeNames(in: context) ?? []
        )
    }
}
