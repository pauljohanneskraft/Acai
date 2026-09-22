import Foundation
import AcaiCore
import AcaiTreeSitter

// MARK: - Record bodies, globals and free functions

extension CFamilyExtractor {

    // MARK: - Record body

    mutating func extractRecordBody(
        _ body: Node, ownerName: String, defaultAccess: AccessLevel,
        members: inout [Member], nestedTypes: inout [TypeDeclaration]
    ) {
        var access = defaultAccess
        // Call sites/assignments resolve after the loop so the scope reflects the full member set.
        var pendingBodies: [(index: Int, body: Node)] = []
        for child in body.namedChildren() {
            switch child.nodeType {
            case "access_specifier":
                access = memberExtractor.accessLevel(from: child) ?? access
            case "field_declaration":
                appendField(child, ownerName: ownerName, access: access,
                            members: &members, nestedTypes: &nestedTypes)
            case "function_definition":
                if var method = memberExtractor.functionMember(from: child, ownerName: ownerName, access: access) {
                    // A constructor's member-initializer list (`: x(compute())`) is a sibling of the
                    // body; walk it so calls made during construction aren't lost.
                    if let initList = child.firstChild(withType: "field_initializer_list") {
                        method.callSites += callSites.callSites(
                            in: initList,
                            scope: CallSiteScope(knownTypeNames: declarations.declaredTypeNames)
                                .merging(parameters: method.parameters))
                    }
                    members.append(method)
                    if let methodBody = child.child(byFieldName: "body") {
                        pendingBodies.append((members.count - 1, methodBody))
                    }
                }
            case "struct_specifier", "union_specifier", "class_specifier", "enum_specifier":
                appendNestedType(child, into: &nestedTypes)
            case "template_declaration":
                appendTemplateMember(child, ownerName: ownerName, access: access,
                                     members: &members, nestedTypes: &nestedTypes)
            default:
                break
            }
        }
        attachBodies(pendingBodies, to: &members)
    }

    /// Resolves and attaches call sites + assignments once the type's full member set is known, so
    /// every stored property is available to the scope.
    private func attachBodies(_ pendingBodies: [(index: Int, body: Node)], to members: inout [Member]) {
        guard !pendingBodies.isEmpty else { return }
        let index = MemberIndex(members: members)
        let scope = CallSiteScope(
            knownProperties: index.propertyTypes,
            knownTypeNames: declarations.declaredTypeNames,
            knownMethodReturnTypes: index.methodReturnTypes
        )
        for pending in pendingBodies where pending.index < members.count {
            // `+=`: a constructor may already carry member-initializer-list call sites set at append time.
            members[pending.index].callSites += callSites.callSites(
                in: pending.body, scope: scope.merging(parameters: members[pending.index].parameters))
            members[pending.index].assignments = assignments.assignments(in: pending.body)
            members[pending.index].fieldReads = fieldReads.reads(in: pending.body, scope: scope)
            members[pending.index].referencedTypeNames = pending.body.referencedTypeNames(in: context)
            members[pending.index].cyclomaticComplexity =
                pending.body.cyclomaticComplexity(branchKinds: Self.branchNodeKinds)
        }
    }

    private mutating func appendField(
        _ node: Node, ownerName: String, access: AccessLevel,
        members: inout [Member], nestedTypes: inout [TypeDeclaration]
    ) {
        if let typeNode = node.child(byFieldName: "type") {
            appendNestedType(typeNode, into: &nestedTypes)
        }
        for declarator in typeReferences.memberDeclarators(of: node) {
            let info = typeReferences.parseDeclarator(declarator)
            guard !info.name.isEmpty else { continue }
            if info.isFunction {
                members.append(
                    memberExtractor.methodMember(node: node, info: info, ownerName: ownerName, access: access))
            } else {
                members.append(memberExtractor.propertyMember(node: node, info: info, access: access))
            }
        }
    }

    @discardableResult
    private mutating func appendNestedType(_ node: Node, into nestedTypes: inout [TypeDeclaration]) -> Bool {
        guard node.child(byFieldName: "body") != nil else { return false }
        switch node.nodeType {
        case "struct_specifier", "union_specifier", "class_specifier":
            if let decl = extractRecord(node) { nestedTypes.append(decl); return true }
        case "enum_specifier":
            if let decl = extractEnum(node) { nestedTypes.append(decl); return true }
        default:
            break
        }
        return false
    }

    private mutating func appendTemplateMember(
        _ node: Node, ownerName: String, access: AccessLevel,
        members: inout [Member], nestedTypes: inout [TypeDeclaration]
    ) {
        for child in node.namedChildren() {
            switch child.nodeType {
            case "function_definition":
                if let method = memberExtractor.functionMember(from: child, ownerName: ownerName, access: access) {
                    members.append(method)
                }
            case "field_declaration":
                appendField(child, ownerName: ownerName, access: access,
                            members: &members, nestedTypes: &nestedTypes)
            case "class_specifier", "struct_specifier", "union_specifier":
                appendNestedType(child, into: &nestedTypes)
            default:
                break
            }
        }
    }

    // MARK: - Top-level globals & prototypes

    mutating func extractTopLevelDeclarators(_ node: Node) {
        for declarator in typeReferences.memberDeclarators(of: node) {
            let info = typeReferences.parseDeclarator(declarator)
            guard !info.name.isEmpty else { continue }
            if info.isFunction {
                declarations.freestandingFunctions.append(
                    memberExtractor.methodMember(node: node, info: info, ownerName: nil, access: .public))
            } else {
                declarations.globalVariables.append(memberExtractor.globalVariable(node: node, info: info))
            }
        }
    }

    func extractFunctionDefinition(_ node: Node, defaultAccess: AccessLevel) -> Member? {
        guard var member = memberExtractor.functionMember(from: node, ownerName: nil, access: defaultAccess) else {
            return nil
        }
        if let body = node.child(byFieldName: "body") {
            let scope = CallSiteScope(knownProperties: [:], knownTypeNames: declarations.declaredTypeNames)
            member.callSites = callSites.callSites(in: body, scope: scope.merging(parameters: member.parameters))
            // Expose the function's typed parameters so a `param->field = …` write inside the body
            // can be attributed to the parameter's struct type; scoped to this one resolution.
            let receiverAssignments = AssignmentResolver(
                syntax: assignmentSyntax.withReceiverTypes(parameterReceiverTypes(member.parameters)))
            member.assignments = receiverAssignments.assignments(in: body)
        }
        return member
    }

    /// Maps each named parameter to its (pointer/reference-stripped) type name. Deliberately
    /// over-inclusive: only parameters actually used as a `->`/`.` assignment receiver are
    /// consulted, and the state analysis filters by the exact receiver type, so listing every
    /// parameter is harmless and avoids depending on declaration order of the struct.
    private func parameterReceiverTypes(_ parameters: [Parameter]) -> [String: String] {
        var map: [String: String] = [:]
        for parameter in parameters where !parameter.internalName.isEmpty {
            if let typeName = parameter.type?.name { map[parameter.internalName] = typeName }
        }
        return map
    }
}
