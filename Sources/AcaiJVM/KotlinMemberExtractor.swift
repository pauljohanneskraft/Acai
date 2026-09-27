import AcaiCore
import AcaiTreeSitter

// MARK: - KotlinMemberExtractor

/// Shapes a `Member` from a function, property, constructor, initializer or enum-entry node,
/// resolving the body's call sites, assignments and field reads against the scope the caller
/// supplies. It never reads `KotlinExtractor`'s declaration state.
struct KotlinMemberExtractor {
    let context: SourceFileContext
    let typeReferences: KotlinTypeReferenceResolver
    let modifiers: KotlinModifiers
    let parameterExtractor: KotlinParameterExtractor
    let assignmentSyntax: KotlinAssignmentSyntax
    let callSites: CallSiteResolver
    let assignments: AssignmentResolver
    let fieldReads: FieldReadResolver
    /// From the pre-pass: a property initialised by constructing one of these gets that type.
    let declaredTypeNames: Set<String>

    /// Kotlin structural decision-point node types for cyclomatic complexity (`when` entries, `if`/
    /// loops, `catch`).
    static let branchNodeKinds: Set<String> = [
        "if_expression", "for_statement", "while_statement", "do_while_statement",
        "when_entry", "catch_block"
    ]

    /// A `when_entry` carrying an `else` keyword is the fallback arm, not a decision.
    static let complexityFallbackMarkers: [String: Set<String>] = ["when_entry": ["else"]]

    // MARK: - Enum Entry

    func enumEntry(_ node: Node) -> EnumCase? {
        guard let nameNode = node.firstChild(withType: "simple_identifier") else { return nil }
        let name = nameNode.text(in: context)
        var rawValue: String?
        if let valueArgs = node.firstChild(withType: "value_arguments") {
            let argsText = valueArgs.text(in: context).trimmingCharacters(in: .whitespaces)
            rawValue = (argsText.hasPrefix("(") && argsText.hasSuffix(")"))
                ? String(argsText.dropFirst().dropLast()) : argsText
        }
        return EnumCase(name: name, rawValue: rawValue, location: node.location(in: context))
    }

    // MARK: - Function Declaration

    func functionDeclaration(_ node: Node, scope: CallSiteScope) -> Member {
        let modifierInfo = modifiers.info(fromParentOf: node)
        let name = node.firstChild(withType: "simple_identifier").map { $0.text(in: context) } ?? "_anonymous"
        let generics = typeReferences.extractTypeParameters(node.firstChild(withType: "type_parameters"))
        let params = parameterExtractor.functionValueParameters(
            node.firstChild(withType: "function_value_parameters")
        )
        let returnType: TypeReference? = {
            guard let returnTypeNode = returnTypeNode(in: node) else { return nil }
            let ref = typeReferences.extractTypeReferenceFromAny(returnTypeNode)
            return ref.name == "Unit" ? nil : ref
        }()

        let body = node.firstChild(withType: "function_body")

        return Member(
            name: name, kind: .method,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            type: returnType, parameters: params,
            genericParameters: generics, annotations: modifierInfo.annotations,
            location: node.location(in: context),
            callSites: callSites.callSites(in: body, scope: scope.merging(parameters: params)),
            assignments: assignments.assignments(in: body),
            fieldReads: fieldReads.reads(in: body, scope: scope),
            referencedTypeNames: body?.referencedTypeNames(in: context) ?? [],
            cyclomaticComplexity: body?.cyclomaticComplexity(
                branchKinds: Self.branchNodeKinds, fallbackMarkers: Self.complexityFallbackMarkers)
        )
    }

    /// The receiver type of an extension function declaration. In `fun String.hello() {}`, `String`
    /// is the receiver type: the AST places it as a type node child followed by an anonymous `"."`
    /// child before the function name.
    func receiverType(of node: Node) -> TypeReference? {
        let children = node.children()
        guard let funIndex = children.firstIndex(where: {
            !$0.isNamed && $0.text(in: context) == "fun"
        }) else { return nil }
        var childIndex = children.index(after: funIndex)
        while childIndex < children.endIndex {
            let child = children[childIndex]
            // Skip generics before the receiver.
            if child.nodeType == "type_parameters" {
                childIndex = children.index(after: childIndex)
                continue
            }
            // A type node followed by "." indicates a receiver type.
            if child.isNamed,
               let nodeType = child.nodeType,
               ["user_type", "nullable_type", "parenthesized_type"].contains(nodeType) {
                let nextIndex = children.index(after: childIndex)
                if nextIndex < children.endIndex,
                   !children[nextIndex].isNamed,
                   children[nextIndex].text(in: context) == "." {
                    return typeReferences.extractTypeReferenceFromAny(child)
                }
            }
            break // Not an extension function.
        }
        return nil
    }

    /// The type node after the parameter list's `:`, if the function declares a return type.
    func returnTypeNode(in node: Node) -> Node? {
        var foundParams = false
        var foundColon = false
        for child in node.children() {
            let childType = child.nodeType
            if childType == "function_value_parameters" {
                foundParams = true
                continue
            }
            if foundParams && !child.isNamed && child.text(in: context) == ":" {
                foundColon = true
                continue
            }
            if foundColon && child.isNamed {
                let typeNodeTypes = [
                    "user_type", "nullable_type",
                    "function_type", "parenthesized_type"
                ]
                if let childType, typeNodeTypes.contains(childType) { return child }
                break
            }
            if childType == "function_body" { break }
        }
        return nil
    }

    // MARK: - Property Declaration

    func propertyDeclaration(
        _ node: Node,
        isComputed: Bool = false,
        scope: CallSiteScope = CallSiteScope()
    ) -> Member {
        let modifierInfo = modifiers.info(fromParentOf: node)
        let isVal = modifiers.bindingKind(of: node) == "val"
        var memberModifiers = modifierInfo.modifiers
        if isVal { memberModifiers.append(.readonly) }

        var name = ""
        var typeRef: TypeReference?

        if let varDecl = node.firstChild(withType: "variable_declaration") {
            name = varDecl.firstChild(withType: "simple_identifier").map { $0.text(in: context) } ?? ""
            typeRef = typeReferences.extractFirstTypeRef(from: varDecl)
        } else {
            name = node.firstChild(withType: "simple_identifier").map { $0.text(in: context) } ?? ""
            typeRef = typeReferences.extractFirstTypeRef(from: node)
        }
        // No explicit `: Type` annotation — infer from a direct construction initializer (`val helper
        // = Helper()`), same heuristic `localBindings` applies to locals. Without this, calls through
        // a composed collaborator field (`helper.doThing()`) can't resolve.
        if typeRef == nil, let constructed = constructedTypeRef(from: initializerNode(of: node)) {
            typeRef = constructed
        }

        // A custom accessor (`get()`/`set()`) nests as a child; walk each so accessor-only calls
        // aren't lost, and treat the property as computed.
        let accessors = node.namedChildren().filter { $0.nodeType == "getter" || $0.nodeType == "setter" }
        var propertyCallSites = callSites.callSites(in: initializerNode(of: node), scope: scope)
        for accessor in accessors {
            propertyCallSites += callSites.callSites(in: accessor, scope: scope)
        }

        return Member(
            name: name, kind: .property,
            accessLevel: modifierInfo.accessLevel, modifiers: memberModifiers,
            type: typeRef,
            isComputed: isComputed || !accessors.isEmpty,
            annotations: modifierInfo.annotations, location: node.location(in: context),
            callSites: propertyCallSites,
            initialValue: initializerValue(of: node),
            referencedTypeNames: initializerNode(of: node)?.referencedTypeNames(in: context) ?? []
        )
    }

    /// Records an `init { … }` block's calls on an `.initializer` member (Kotlin's constructor body),
    /// so calls made only during construction aren't lost.
    func anonymousInitializer(_ node: Node, scope: CallSiteScope) -> Member {
        Member(
            name: "init", kind: .initializer, accessLevel: .internal,
            location: node.location(in: context),
            callSites: callSites.callSites(in: node, scope: scope)
        )
    }

    /// The property's initializer expression node (the node after the anonymous `=`), if present.
    private func initializerNode(of node: Node) -> Node? {
        var foundEq = false
        for child in node.children() {
            if !child.isNamed && child.text(in: context) == "=" {
                foundEq = true
                continue
            }
            if foundEq { return child }
        }
        return nil
    }

    /// Classifies the property's initializer expression (the node after the anonymous `=` token). The
    /// expression may itself be an anonymous token (`null`), so namedness isn't required.
    private func initializerValue(of node: Node) -> VariableAssignment.Value? {
        initializerNode(of: node).map { assignmentSyntax.classifyValue($0) }
    }

    /// Infers a property's type from a direct construction initializer (`Helper()`, no navigation so
    /// `foo.Bar()` isn't mistaken for one), when the callee is a same-file declared type.
    private func constructedTypeRef(from initializerNode: Node?) -> TypeReference? {
        guard let call = initializerNode, call.nodeType == "call_expression",
              call.firstChild(withType: "navigation_expression") == nil,
              let callee = call.firstChild(withType: "simple_identifier"),
              declaredTypeNames.contains(callee.text(in: context))
        else { return nil }
        return TypeReference(name: callee.text(in: context))
    }

    // MARK: - Secondary Constructor

    func secondaryConstructor(_ node: Node, scope: CallSiteScope) -> Member {
        let modifierInfo = modifiers.info(fromParentOf: node)
        let params = parameterExtractor.functionValueParameters(
            node.firstChild(withType: "function_value_parameters")
        )
        // The constructor body has no `block` wrapper; statements sit inline under this node.
        let body = node.firstChild(withType: "block")
            ?? node.firstChild(withType: "statements")
        return Member(
            name: "init", kind: .initializer,
            accessLevel: modifierInfo.accessLevel,
            parameters: params, location: node.location(in: context),
            callSites: callSites.callSites(in: body, scope: scope.merging(parameters: params)),
            assignments: assignments.assignments(in: body),
            fieldReads: fieldReads.reads(in: body, scope: scope)
        )
    }
}
