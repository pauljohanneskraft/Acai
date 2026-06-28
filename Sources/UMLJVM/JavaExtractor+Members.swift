import UMLCore
import UMLTreeSitter

// MARK: - Body & Member Extraction

extension JavaExtractor {

    private func buildPropertyMap(from existingMembers: [Member], node: Node) -> [String: String] {
        var knownProperties: [String: String] = [:]
        for member in existingMembers where member.kind == .property {
            if let typeName = member.type?.name { knownProperties[member.name] = typeName }
        }
        for child in node.children() where child.nodeType == "field_declaration" {
            for field in extractFieldDeclaration(child) where field.kind == .property {
                if let typeName = field.type?.name { knownProperties[field.name] = typeName }
            }
        }
        return knownProperties
    }

    mutating func extractNestedTypeFromChild(
        _ child: Node,
        nodeType: String,
        parentQualifiedName: String
    ) -> TypeDeclaration? {
        // Temporarily set namespace to the parent type's qualified name
        // so nested types receive correct IDs (e.g. `pkg.Outer.Inner`).
        let savedNamespace = currentNamespace
        currentNamespace = parentQualifiedName
        defer { currentNamespace = savedNamespace }

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

    /// Roles for dispatching child nodes within a type body.
    private enum BodyChildRole {
        case method
        case constructor
        case field
        case nestedType
        case enumConstant
        case enumBodyDeclarations
        case annotationTypeElement
    }

    /// Dispatch table for class/record bodies.
    private static let classBodyDispatch: [String: BodyChildRole] = [
        "method_declaration": .method,
        "constructor_declaration": .constructor,
        "field_declaration": .field,
        "class_declaration": .nestedType,
        "interface_declaration": .nestedType,
        "enum_declaration": .nestedType,
        "record_declaration": .nestedType,
        "annotation_type_declaration": .nestedType
    ]

    /// Dispatch table for interface bodies.
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

    /// Dispatch table for enum bodies.
    private static let enumBodyDispatch: [String: BodyChildRole] = [
        "enum_constant": .enumConstant,
        "enum_body_declarations": .enumBodyDeclarations,
        "method_declaration": .method,
        "constructor_declaration": .constructor,
        "field_declaration": .field,
        "class_declaration": .nestedType,
        "interface_declaration": .nestedType
    ]

    /// Dispatch table for annotation type bodies.
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

    /// Bundles the mutable accumulator state passed through body extraction.
    struct BodyExtractionContext {
        var members: [Member] = []
        var nestedTypes: [TypeDeclaration] = []
        var enumCases: [EnumCase] = []
        let parentQualifiedName: String
        var scope: CallSiteScope = CallSiteScope()
    }

    /// Iterates over body children, dispatching each to the appropriate handler via the dispatch table.
    private mutating func extractBodyMembers(
        _ node: Node,
        context: inout BodyExtractionContext,
        dispatch: [String: BodyChildRole]
    ) {
        for child in node.children() {
            guard let nodeType = child.nodeType,
                  let role = dispatch[nodeType] else { continue }
            dispatchBodyChild(role, child: child, nodeType: nodeType, context: &context)
        }
    }

    /// Executes the handler for a single body child based on its role.
    private mutating func dispatchBodyChild(
        _ role: BodyChildRole,
        child: Node,
        nodeType: String,
        context: inout BodyExtractionContext
    ) {
        switch role {
        case .method:
            appendIfPresent(
                extractMethodDeclaration(child, scope: context.scope),
                to: &context.members
            )
        case .constructor:
            appendIfPresent(
                extractConstructorDeclaration(child, scope: context.scope),
                to: &context.members
            )
        case .field:
            context.members.append(contentsOf: extractFieldDeclaration(child))
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
            appendIfPresent(extractAnnotationTypeElement(child), to: &context.members)
        }
    }

    // MARK: - Body Extraction Wrappers

    mutating func extractClassBody(
        _ node: Node,
        context: inout BodyExtractionContext
    ) {
        context.scope = CallSiteScope(
            knownProperties: buildPropertyMap(from: context.members, node: node),
            knownTypeNames: declaredTypeNames
        )
        extractBodyMembers(node, context: &context, dispatch: Self.classBodyDispatch)
    }

    mutating func extractInterfaceBody(
        _ node: Node,
        context: inout BodyExtractionContext
    ) {
        extractBodyMembers(node, context: &context, dispatch: Self.interfaceBodyDispatch)
    }

    mutating func extractEnumBody(
        _ node: Node,
        context: inout BodyExtractionContext
    ) {
        extractBodyMembers(node, context: &context, dispatch: Self.enumBodyDispatch)
    }

    mutating func extractAnnotationTypeBody(
        _ node: Node,
        context: inout BodyExtractionContext
    ) {
        extractBodyMembers(node, context: &context, dispatch: Self.annotationTypeBodyDispatch)
    }

    private func extractAnnotationTypeElement(_ node: Node) -> Member? {
        let modifierInfo = extractModifiersFromParent(node)
        let nodeLoc = loc(node)
        var returnType: TypeReference?
        var name = ""

        if let typeNode = node.child(byFieldName: "type") { returnType = extractTypeReference(typeNode) }
        if let nameNode = node.child(byFieldName: "name") { name = text(nameNode) }
        guard !name.isEmpty else { return nil }

        return Member(
            name: name, kind: .method,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            type: returnType, annotations: modifierInfo.annotations, location: nodeLoc
        )
    }

    // MARK: - Enum Constant

    private func extractEnumConstant(_ node: Node) -> EnumCase? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = text(nameNode)
        guard !name.isEmpty else { return nil }
        let nodeLoc = loc(node)

        var arguments: [Parameter] = []
        if let argsNode = node.child(byFieldName: "arguments") {
            arguments = extractArgumentsAsParameters(argsNode)
        }

        return EnumCase(name: name, associatedValues: arguments, location: nodeLoc)
    }

    private func extractArgumentsAsParameters(_ node: Node) -> [Parameter] {
        return node.namedChildren().compactMap { child in
            let argText = text(child)
            return argText.isEmpty ? nil : Parameter(internalName: argText)
        }
    }

    // MARK: - Method Declaration

    func extractMethodDeclaration(
        _ node: Node,
        scope: CallSiteScope = CallSiteScope()
    ) -> Member? {
        let modifierInfo = extractModifiersFromParent(node)
        let nodeLoc = loc(node)

        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = text(nameNode)
        guard !name.isEmpty else { return nil }

        var returnType: TypeReference?
        if let typeNode = node.child(byFieldName: "type") {
            returnType = extractTypeReference(typeNode)
        }

        let genericParams = extractTypeParameters(from: node)
        var parameters: [Parameter] = []
        if let paramsNode = node.child(byFieldName: "parameters") {
            parameters = extractFormalParameters(paramsNode)
        }

        let body = node.child(byFieldName: "body")
        let callSites = extractCallSites(from: body, scope: scope)

        return Member(
            name: name, kind: .method,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            type: returnType, parameters: parameters, genericParameters: genericParams,
            annotations: modifierInfo.annotations, location: nodeLoc,
            callSites: callSites,
            assignments: extractAssignments(from: body),
            referencedTypeNames: referencedTypeNames(in: body)
        )
    }

    // MARK: - Constructor Declaration

    func extractConstructorDeclaration(
        _ node: Node,
        scope: CallSiteScope = CallSiteScope()
    ) -> Member? {
        let modifierInfo = extractModifiersFromParent(node)
        let nodeLoc = loc(node)

        let name = node.child(byFieldName: "name").map { text($0) } ?? ""
        let genericParams = extractTypeParameters(from: node)
        var parameters: [Parameter] = []
        if let paramsNode = node.child(byFieldName: "parameters") {
            parameters = extractFormalParameters(paramsNode)
        }

        let body = node.child(byFieldName: "body")
        let callSites = extractCallSites(from: body, scope: scope)

        return Member(
            name: name, kind: .initializer,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            parameters: parameters, genericParameters: genericParams,
            annotations: modifierInfo.annotations, location: nodeLoc,
            callSites: callSites,
            assignments: extractAssignments(from: body),
            referencedTypeNames: referencedTypeNames(in: body)
        )
    }

    // MARK: - Field Declaration

    func extractFieldDeclaration(_ node: Node) -> [Member] {
        let modifierInfo = extractModifiersFromParent(node)
        let nodeLoc = loc(node)

        var fieldType: TypeReference?
        if let typeNode = node.child(byFieldName: "type") {
            fieldType = extractTypeReference(typeNode)
        }

        // Collect all variable_declarator children (handles: int x, y, z;)
        let declarators = node.allChildren(withType: "variable_declarator")
        if !declarators.isEmpty {
            return declarators.compactMap {
                extractVariableDeclarator($0, fieldType: fieldType, modifierInfo: modifierInfo, loc: nodeLoc)
            }
        }

        // Fallback: try declarator field name
        if let declaratorNode = node.child(byFieldName: "declarator") {
            if let member = extractVariableDeclarator(
                declaratorNode, fieldType: fieldType, modifierInfo: modifierInfo, loc: nodeLoc
            ) {
                return [member]
            }
        }
        return []
    }

    private func extractVariableDeclarator(
        _ node: Node,
        fieldType: TypeReference?,
        modifierInfo: ModifierInfo,
        loc: SourceLocation
    ) -> Member? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let name = text(nameNode)
        guard !name.isEmpty else { return nil }

        var actualType = fieldType
        if let dimensionsNode = node.child(byFieldName: "dimensions") {
            let dimText = text(dimensionsNode)
            let bracketPairs = dimText.components(separatedBy: "[]").count - 1
            if bracketPairs > 0, let arrayFieldType = actualType {
                actualType = TypeReference(
                    name: arrayFieldType.name, genericArguments: arrayFieldType.genericArguments,
                    isOptional: arrayFieldType.isOptional, isArray: true
                )
            }
        }

        return Member(
            name: name, kind: .property,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            type: actualType, annotations: modifierInfo.annotations, location: loc,
            initialValue: node.child(byFieldName: "value").map { classifyValue($0) },
            referencedTypeNames: referencedTypeNames(in: node.child(byFieldName: "value"))
        )
    }

    // MARK: - Formal Parameters

    func extractFormalParameters(_ node: Node) -> [Parameter] {
        var params: [Parameter] = []
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "formal_parameter":
                if let param = extractFormalParameter(child) { params.append(param) }
            case "spread_parameter":
                if let param = extractSpreadParameter(child) { params.append(param) }
            case "receiver_parameter":
                break // Skip 'this' parameter
            default:
                break
            }
        }
        return params
    }

    func extractFormalParameter(_ node: Node) -> Parameter? {
        var paramType: TypeReference?
        var name = ""
        var paramModifiers: [Modifier] = []

        if let modNode = node.firstChild(withType: "modifiers") {
            paramModifiers = extractModifiers(modNode).modifiers
        }

        if let typeNode = node.child(byFieldName: "type") { paramType = extractTypeReference(typeNode) }
        if let nameNode = node.child(byFieldName: "name") { name = text(nameNode) }
        guard !name.isEmpty else { return nil }

        if let dimensionsNode = node.child(byFieldName: "dimensions") {
            let dimText = text(dimensionsNode)
            if !dimText.isEmpty, let parameterType = paramType {
                paramType = TypeReference(
                    name: parameterType.name, genericArguments: parameterType.genericArguments,
                    isOptional: parameterType.isOptional, isArray: true
                )
            }
        }

        return Parameter(internalName: name, type: paramType, modifiers: paramModifiers)
    }

    private func extractSpreadParameter(_ node: Node) -> Parameter? {
        var paramType: TypeReference?
        var name = ""
        if let typeNode = node.child(byFieldName: "type") { paramType = extractTypeReference(typeNode) }
        if let nameNode = node.child(byFieldName: "name") { name = text(nameNode) }
        // Fallback: last named child is usually the name in varargs
        if name.isEmpty, let lastNamed = node.namedChildren().last { name = text(lastNamed) }
        guard !name.isEmpty else { return nil }
        return Parameter(internalName: name, type: paramType, isVariadic: true)
    }
}
