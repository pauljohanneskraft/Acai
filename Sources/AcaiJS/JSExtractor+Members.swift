import AcaiCore
import AcaiTreeSitter

// MARK: - Members & Type Extraction

extension JSExtractor {

    // MARK: - Class Body

    func parseClassBody(_ bodyNode: Node, into typeDecl: inout TypeDeclaration) {
        let scope = CallSiteScope(
            knownProperties: memberExtractor.propertyMap(fromBody: bodyNode),
            knownTypeNames: declarations.declaredTypeNames,
            knownMethodReturnTypes: memberExtractor.methodReturnTypeMap(fromBody: bodyNode)
        )

        for child in bodyNode.children() {
            guard let childType = child.nodeType else { continue }
            if let member = extractClassBodyMember(child, childType: childType, scope: scope, typeDecl: &typeDecl) {
                typeDecl.members.append(member)
            }
        }
    }

    private func extractClassBodyMember(
        _ child: Node,
        childType: String,
        scope: CallSiteScope,
        typeDecl: inout TypeDeclaration
    ) -> Member? {
        switch childType {
        case "method_definition", "abstract_method_definition":
            var member = methodDefinition(child, scope: scope)
            if childType == "abstract_method_definition", isTypeScript,
               !member.modifiers.contains(.abstract) {
                member.modifiers.append(.abstract)
            }
            if member.kind == .initializer, isTypeScript {
                typeDecl.members.append(contentsOf: memberExtractor.constructorParameterProperties(child))
            }
            return member

        case "field_definition", "public_field_definition":
            return fieldDefinition(child, scope: scope)

        case "method_signature" where isTypeScript:
            return memberExtractor.methodSignature(child)

        case "abstract_method_signature" where isTypeScript:
            var member = memberExtractor.methodSignature(child)
            if !member.modifiers.contains(.abstract) {
                member.modifiers.append(.abstract)
            }
            return member

        case "property_signature" where isTypeScript:
            return memberExtractor.propertySignature(child)

        default:
            return nil
        }
    }

    // MARK: - Method Definition (Orchestration)

    private func methodDefinition(_ node: Node, scope: CallSiteScope) -> Member {
        let generics = isTypeScript ? typeReferences.extractTypeParameters(node) : []
        let params = node.child(byFieldName: "parameters").map { parameterExtractor.parameters($0) } ?? []
        let returnType = isTypeScript ? typeReferences.extractReturnTypeAnnotation(node) : nil

        let body = node.child(byFieldName: "body")
        let mergedScope = scope.merging(parameters: params)
        return memberExtractor.methodDefinition(
            node,
            generics: generics,
            parameters: params,
            returnType: returnType,
            references: .init(
                callSites: callSites.callSites(in: body, scope: mergedScope),
                assignments: assignments.assignments(in: body),
                fieldReads: fieldReads.reads(in: body, scope: mergedScope),
                referencedTypeNames: body?.referencedTypeNames(in: context) ?? [],
                cyclomaticComplexity: body?.cyclomaticComplexity(branchKinds: JSMemberExtractor.branchNodeKinds)
            )
        )
    }

    // MARK: - Field Definition (Orchestration)

    private func fieldDefinition(_ node: Node, scope: CallSiteScope = CallSiteScope()) -> Member {
        let value = node.child(byFieldName: "value")
        return memberExtractor.fieldDefinition(
            node,
            references: .init(
                callSites: callSites.callSites(in: value, scope: scope),
                initialValue: value.map { assignmentSyntax.classifyValue($0) },
                referencedTypeNames: value?.referencedTypeNames(in: context) ?? []
            )
        )
    }

    // MARK: - Top-Level Variable Declaration (Orchestration)

    /// A top-level (module-scope) `const`/`let`/`var` declarator, or one inside a TS `namespace`
    /// body (mirroring how a nested top-level function there still feeds `freestandingFunctions`).
    func extractGlobalVariable(_ node: Node, name: String, isExported: Bool) -> Member {
        let value = node.child(byFieldName: "value")
        return memberExtractor.globalVariable(
            node, name: name, isExported: isExported,
            references: .init(
                callSites: callSites.callSites(
                    in: value, scope: CallSiteScope(knownTypeNames: declarations.declaredTypeNames)),
                initialValue: value.map { assignmentSyntax.classifyValue($0) },
                referencedTypeNames: value?.referencedTypeNames(in: context) ?? []
            )
        )
    }

    // MARK: - Type Alias Declaration

    func extractTypeAliasDeclaration(_ node: Node, isExported: Bool) -> TypeDeclaration {
        let nodeLoc = node.location(in: context)
        let nameNode = node.child(byFieldName: "name")
        let name = nameNode.map { $0.text(in: context) } ?? ""
        let generics = typeReferences.extractTypeParameters(node)

        var targetText = ""
        if let valueNode = node.child(byFieldName: "value") {
            targetText = valueNode.text(in: context)
        }

        return TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .typeAlias,
            accessLevel: isExported ? .public : .internal,
            genericParameters: generics,
            inheritedTypes: targetText.isEmpty ? [] : [TypeReference(name: targetText)],
            location: nodeLoc
        )
    }

    // MARK: - Enum Declaration

    func extractEnumDeclaration(_ node: Node, isExported: Bool) -> TypeDeclaration {
        let nodeLoc = node.location(in: context)
        let nameNode = node.child(byFieldName: "name")
        let name = nameNode.map { $0.text(in: context) } ?? ""

        var typeDecl = TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .enum,
            accessLevel: isExported ? .public : .internal,
            location: nodeLoc
        )

        if let body = node.child(byFieldName: "body") {
            for child in body.namedChildren() {
                guard let childType = child.nodeType else { continue }
                if childType == "enum_assignment" {
                    let caseName: String
                    if let nameChild = child.child(byFieldName: "name") {
                        caseName = nameChild.text(in: context)
                    } else {
                        caseName = child.namedChildren().first.map { $0.text(in: context) } ?? ""
                    }
                    var rawValue: String?
                    if let valueChild = child.child(byFieldName: "value") {
                        rawValue = valueChild.text(in: context)
                    }
                    typeDecl.enumCases.append(EnumCase(name: caseName, rawValue: rawValue))
                } else if childType == "property_identifier" || childType == "identifier" {
                    typeDecl.enumCases.append(EnumCase(name: child.text(in: context)))
                }
            }
        }
        return typeDecl
    }

    // MARK: - Module / Namespace

    mutating func extractModule(_ node: Node, isExported: Bool) -> [TypeDeclaration] {
        let name = node.child(byFieldName: "name").map { $0.text(in: context) } ?? "_Module"
        var nestedTypes: [TypeDeclaration] = []
        var nestedFunctions: [Member] = []

        if let body = node.child(byFieldName: "body") {
            for child in body.children() {
                guard let childType = child.nodeType else { continue }
                if childType == "export_statement" {
                    let isDefault = child.hasDirectChildText("default", in: context)
                    let exportDecorators = memberExtractor.decorators(child)
                    for exportChild in child.children() {
                        let (newTypes, newFunctions) = dispatchDeclaration(
                        exportChild, isExported: true, isDefault: isDefault,
                        decorators: exportDecorators, namespace: name
                    )
                        nestedTypes += newTypes; nestedFunctions += newFunctions
                    }
                } else {
                    let (newTypes, newFunctions) = dispatchDeclaration(child, isExported: false, namespace: name)
                    nestedTypes += newTypes; nestedFunctions += newFunctions
                }
            }
        }

        declarations.freestandingFunctions.append(contentsOf: nestedFunctions)
        let nsDecl = TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .module,
            accessLevel: isExported ? .public : .internal,
            nestedTypes: nestedTypes
        )
        return [nsDecl]
    }

    // MARK: - Function Declaration

    func extractFunctionDeclaration(_ node: Node, isExported: Bool) -> Member {
        let nodeLoc = node.location(in: context)
        let name = node.child(byFieldName: "name").map { $0.text(in: context) } ?? "_anonymous"
        var modifiers: [Modifier] = []
        if node.hasDirectChildText("async", in: context) { modifiers.append(.async) }
        let generics = isTypeScript ? typeReferences.extractTypeParameters(node) : []
        let params = node.child(byFieldName: "parameters").map { parameterExtractor.parameters($0) } ?? []
        let returnType = isTypeScript ? typeReferences.extractReturnTypeAnnotation(node) : nil
        // A freestanding function has no enclosing instance, so only file-level type names resolve
        // receivers; its body is still walked so its outgoing calls (bare, `Type.method()`, …) count.
        let bodyCallSites = callSites.callSites(
            in: node.child(byFieldName: "body"), scope: CallSiteScope(knownTypeNames: declarations.declaredTypeNames))
        return Member(
            name: name, kind: .method, accessLevel: isExported ? .public : .internal,
            modifiers: modifiers, type: returnType, parameters: params,
            genericParameters: generics, location: nodeLoc, callSites: bodyCallSites)
    }

    // MARK: - Prototype Pattern Detection (JS only)

    mutating func detectPrototypePatterns(_ root: Node) {
        let assignments = collectPrototypeAssignments(root)
        for assignment in assignments {
            applyPrototypeAssignment(assignment)
        }
    }

    private func collectPrototypeAssignments(
        _ root: Node
    ) -> [(className: String, memberName: String, node: Node)] {
        var results: [(className: String, memberName: String, node: Node)] = []
        for child in root.children() {
            guard child.nodeType == "expression_statement",
                  let expr = child.namedChildren().first,
                  expr.nodeType == "assignment_expression",
                  let leftNode = expr.child(byFieldName: "left"),
                  leftNode.nodeType == "member_expression" else { continue }
            let leftText = leftNode.text(in: context)
            guard let protoRange = leftText.range(of: ".prototype.") else { continue }
            let className = String(leftText[leftText.startIndex..<protoRange.lowerBound])
            let memberName = String(leftText[protoRange.upperBound...])
            if !className.isEmpty, !memberName.isEmpty {
                results.append((className, memberName, expr))
            }
        }
        return results
    }

    private mutating func applyPrototypeAssignment(
        _ assignment: (className: String, memberName: String, node: Node)
    ) {
        ensureTypeExists(name: assignment.className)
        let member = memberExtractor.prototypeMember(
            name: assignment.memberName, assignedValue: assignment.node.child(byFieldName: "right"))
        guard let index = declarations.types.firstIndex(where: { $0.name == assignment.className }) else { return }
        declarations.types[index].members.append(member)
    }

    private mutating func ensureTypeExists(name: String) {
        if !declarations.types.contains(where: { $0.name == name }) {
            declarations.types.append(
                TypeDeclaration(id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .internal))
        }
    }
}
