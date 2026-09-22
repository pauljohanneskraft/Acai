import AcaiCore
import AcaiTreeSitter

// MARK: - Body Extraction

extension DartExtractor {

    private mutating func extractNestedType(
        _ child: Node, nodeType: String
    ) -> TypeDeclaration? {
        switch nodeType {
        case "class_definition":
            return extractClassDefinition(child)
        case "enum_declaration":
            return extractEnumDeclaration(child)
        case "mixin_declaration":
            return extractMixinDeclaration(child)
        default:
            return nil
        }
    }

    @discardableResult
    private mutating func processClassMemberNode(
        _ child: Node,
        nodeType: String,
        members: inout [Member],
        nestedTypes: inout [TypeDeclaration],
        parentName: String
    ) -> Bool {
        if let member = memberExtractor.member(fromSignature: child, nodeType: nodeType, parentName: parentName) {
            members.append(member)
            return true
        }
        if nodeType == "static_final_declaration_list"
            || nodeType == "initialized_identifier_list" {
            members.append(contentsOf: extractFieldDeclarations(child))
            return true
        }
        if let typeDecl = extractNestedType(child, nodeType: nodeType) {
            nestedTypes.append(typeDecl)
            return true
        }
        return false
    }

    mutating func extractClassBody(
        _ node: Node,
        members: inout [Member],
        nestedTypes: inout [TypeDeclaration],
        parentName: String
    ) {
        // A member's `function_body` is a *sibling* of its signature node, paired with whichever
        // member the immediately preceding child produced.
        var previousChildAddedMember = false
        // Call sites are resolved after the loop so the scope reflects the type's full member set.
        var pendingBodies: [(index: Int, body: Node)] = []
        var pendingAnnotations: [String] = []
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            if nodeType == "annotation" {
                pendingAnnotations.append(annotations.text(child))
                continue
            }
            if nodeType == "function_body" {
                attachFunctionBody(
                    child, previousChildAddedMember: previousChildAddedMember,
                    members: &members, pendingBodies: &pendingBodies
                )
                previousChildAddedMember = false
                continue
            }
            let countBefore = members.count
            if nodeType == "declaration" {
                extractClassMemberDeclaration(
                    child, members: &members, nestedTypes: &nestedTypes, parentName: parentName
                )
            } else {
                processClassMemberNode(
                    child, nodeType: nodeType, members: &members,
                    nestedTypes: &nestedTypes, parentName: parentName
                )
            }
            annotations.assign(pendingAnnotations, toMembersFrom: countBefore, in: &members)
            pendingAnnotations = []
            previousChildAddedMember = members.count == countBefore + 1
            // A constructor's initializer list (`: x = compute()`) lives inside `method_signature`;
            // walk it so its calls aren't lost. Runs before `this`, so file-level type names resolve
            // its static/top-level receivers.
            if previousChildAddedMember, let initializers = child.firstChild(withType: "initializers") {
                appendInitializerListCallSites(initializers, to: &members)
            }
        }
        attachCallSites(pendingBodies, to: &members)
        markBodylessMethodsAbstract(&members, bodiedIndices: Set(pendingBodies.map(\.index)))
    }

    /// Handles `declaration` nodes inside class bodies: `[modifiers] [type] [nullable_type?]
    /// (initialized_identifier_list | static_final_declaration_list)`. Extracts type/modifiers
    /// first, then propagates them to field extraction.
    private mutating func extractClassMemberDeclaration(
        _ node: Node,
        members: inout [Member],
        nestedTypes: inout [TypeDeclaration],
        parentName: String
    ) {
        let info = typeReferences.declarationInfo(node)

        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            if nodeType == "initialized_identifier_list" {
                members.append(contentsOf: extractFieldsFromIdentifierList(child, info: info))
            } else if nodeType == "static_final_declaration_list" {
                members.append(contentsOf: extractStaticFinalFields(child, info: info))
            } else if processClassMemberNode(
                child, nodeType: nodeType, members: &members,
                nestedTypes: &nestedTypes, parentName: parentName
            ) {
                continue
            } else if let fields = extractFieldFromDeclarationChild(child) {
                members.append(contentsOf: fields)
            }
        }
    }

    /// Attaches a `function_body` sibling to the member it belongs to: assignments extracted from
    /// its statements, and `.async` when the body carries an `async`/`async*`/`sync*` marker.
    private func attachFunctionBody(
        _ node: Node,
        previousChildAddedMember: Bool,
        members: inout [Member],
        pendingBodies: inout [(index: Int, body: Node)]
    ) {
        guard previousChildAddedMember, !members.isEmpty else { return }
        members[members.count - 1].assignments = assignments.assignments(in: node)
        if isAsyncFunctionBody(node) {
            members[members.count - 1].modifiers.append(.async)
        }
        pendingBodies.append((members.count - 1, node))
    }

    // MARK: - Enum Body

    mutating func extractEnumBody(
        _ node: Node,
        enumCases: inout [EnumCase],
        members: inout [Member],
        parentName: String
    ) {
        var ignored: [TypeDeclaration] = []
        // Same signature/body sibling pairing as `extractClassBody`.
        var previousChildAddedMember = false
        var pendingBodies: [(index: Int, body: Node)] = []
        var pendingAnnotations: [String] = []
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            if nodeType == "annotation" {
                pendingAnnotations.append(annotations.text(child))
                continue
            }
            let countBefore = members.count
            switch nodeType {
            case "enum_constant":
                if let enumCase = memberExtractor.enumConstant(child) { enumCases.append(enumCase) }
            case "function_body":
                attachFunctionBody(
                    child, previousChildAddedMember: previousChildAddedMember,
                    members: &members, pendingBodies: &pendingBodies
                )
            case "declaration":
                extractClassMemberDeclaration(
                    child, members: &members, nestedTypes: &ignored, parentName: parentName
                )
            default:
                processClassMemberNode(
                    child, nodeType: nodeType, members: &members,
                    nestedTypes: &ignored, parentName: parentName
                )
            }
            annotations.assign(pendingAnnotations, toMembersFrom: countBefore, in: &members)
            pendingAnnotations = []
            previousChildAddedMember = members.count == countBefore + 1
            // A constructor's initializer list (`: x = compute()`) lives inside `method_signature`;
            // walk it so its calls aren't lost. Runs before `this`, so file-level type names resolve
            // its static/top-level receivers.
            if previousChildAddedMember, let initializers = child.firstChild(withType: "initializers") {
                appendInitializerListCallSites(initializers, to: &members)
            }
        }
        attachCallSites(pendingBodies, to: &members)
    }

    // MARK: - Body References

    /// Appends a constructor initializer-list's call sites (`: x = compute()`) to the just-appended
    /// member, with that member's own parameters available as receivers.
    private func appendInitializerListCallSites(_ initializers: Node, to members: inout [Member]) {
        let lastIndex = members.count - 1
        members[lastIndex].callSites += callSites.callSites(
            in: initializers,
            scope: CallSiteScope(knownTypeNames: declarations.declaredTypeNames)
                .merging(parameters: members[lastIndex].parameters))
    }

    /// Resolves and attaches call sites for the recorded method bodies, using a scope built
    /// from the type's fully-extracted members (so all stored properties are known) plus the
    /// current file's known type names.
    private func attachCallSites(_ pendingBodies: [(index: Int, body: Node)], to members: inout [Member]) {
        guard !pendingBodies.isEmpty else { return }
        let index = MemberIndex(members: members)
        let scope = CallSiteScope(
            knownProperties: index.propertyTypes,
            knownTypeNames: declarations.declaredTypeNames,
            knownMethodReturnTypes: index.methodReturnTypes
        )
        for pending in pendingBodies where pending.index < members.count {
            // `+=`: a constructor may already carry initializer-list call sites from the body walk.
            members[pending.index].callSites += callSites.callSites(
                in: pending.body, scope: scope.merging(parameters: members[pending.index].parameters))
            members[pending.index].fieldReads = fieldReads.reads(in: pending.body, scope: scope)
            members[pending.index].referencedTypeNames = pending.body.referencedTypeNames(in: context)
            members[pending.index].cyclomaticComplexity =
                pending.body.cyclomaticComplexity(branchKinds: Self.branchNodeKinds)
        }
    }

    /// A Dart method with no paired body is abstract (a body-less method is only legal as an abstract
    /// requirement); mark it so the dead-code scan treats it as a reachable-by-contract member — the
    /// analogue of an interface requirement, which Dart expresses with abstract classes.
    private func markBodylessMethodsAbstract(_ members: inout [Member], bodiedIndices: Set<Int>) {
        for index in members.indices
        where members[index].kind == .method
            && !bodiedIndices.contains(index)
            && !members[index].modifiers.contains(.abstract) {
            members[index].modifiers.append(.abstract)
        }
    }
}
