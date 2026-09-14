import AcaiCore
import AcaiTreeSitter

// MARK: - Members (methods, fields, self.x synthesis)

extension PythonExtractor {

    mutating func parseClassBody(_ body: Node, into decl: inout TypeDeclaration) {
        for child in body.namedChildren() {
            if child.nodeType == "class_definition" {
                decl.nestedTypes.append(extractClass(child, decorators: []))
            } else if child.nodeType == "decorated_definition",
                      let def = child.child(byFieldName: "definition"), def.nodeType == "class_definition" {
                decl.nestedTypes.append(extractClass(def, decorators: extractDecorators(child)))
            }
        }

        let methodNodes = collectMethodNodes(body)

        // A class-body initializer can't reference `self`, so file-level type names are the only
        // resolvable receivers.
        var fields = collectClassBodyFields(body, scope: CallSiteScope(knownTypeNames: declaredTypeNames))
        let existing = Set(fields.map(\.name))
        fields.append(contentsOf: memberExtractor.synthesizeSelfFields(
            fromMethods: methodNodes, existing: existing, declaredTypeNames: declaredTypeNames,
            accessLevel: accessLevel(forName:)
        ))

        let scope = CallSiteScope(
            knownProperties: memberExtractor.propertyMap(from: fields),
            knownTypeNames: declaredTypeNames,
            // Python fields are frequently untyped (`self.x = …`), so the typed `propertyMap` misses
            // them — pass every field name so field-read capture (issue #111) sees them all.
            knownPropertyNames: Set(fields.map(\.name)),
            knownMethodReturnTypes: memberExtractor.methodReturnTypeMap(fromMethodNodes: methodNodes)
        )

        decl.members.append(contentsOf: fields)
        for method in methodNodes {
            decl.members.append(extractCallable(method.node, decorators: method.decorators, scope: scope))
        }
    }

    func collectMethodNodes(_ body: Node) -> [(node: Node, decorators: [String])] {
        var result: [(node: Node, decorators: [String])] = []
        for child in body.namedChildren() {
            if child.nodeType == "function_definition" {
                result.append((child, []))
            } else if child.nodeType == "decorated_definition",
                      let def = child.child(byFieldName: "definition"), def.nodeType == "function_definition" {
                result.append((def, extractDecorators(child)))
            }
        }
        return result
    }

    // MARK: - Class-body fields

    private func collectClassBodyFields(_ body: Node, scope: CallSiteScope) -> [Member] {
        let resolver = typeReferenceResolver
        var fields: [Member] = []
        for child in body.namedChildren() where child.nodeType == "expression_statement" {
            for assign in child.namedChildren() where assign.nodeType == "assignment" {
                guard let left = assign.child(byFieldName: "left"), left.nodeType == "identifier" else { continue }
                let name = text(left)
                let type = assign.child(byFieldName: "type").flatMap { resolver.resolve(fromTypeField: $0) }
                let initial = assign.child(byFieldName: "right").map { classifyValue($0) }
                fields.append(memberExtractor.field(
                    name: name,
                    type: type,
                    accessLevel: accessLevel(forName: name),
                    location: loc(assign),
                    callSites: extractCallSites(from: assign.child(byFieldName: "right"), scope: scope),
                    initialValue: initial,
                    referencedTypeNames: referencedTypeNames(in: assign.child(byFieldName: "right"))
                ))
            }
        }
        return fields
    }

    // MARK: - Methods & functions

    func extractCallable(_ node: Node, decorators: [String], scope: CallSiteScope) -> Member {
        let params = node.child(byFieldName: "parameters").map { parameterExtractor.parameters($0) } ?? []
        let returnType = node.child(byFieldName: "return_type")
            .flatMap { typeReferenceResolver.resolve(fromTypeField: $0) }
        let name = node.child(byFieldName: "name").map { text($0) } ?? "_anonymous"
        let body = node.child(byFieldName: "body")

        return memberExtractor.callable(
            node,
            signature: .init(
                decorators: decorators, parameters: params, returnType: returnType,
                accessLevel: accessLevel(forName: name)
            ),
            references: .init(
                callSites: extractCallSites(from: body, scope: scope.merging(parameters: params)),
                assignments: extractAssignments(from: body),
                fieldReads: fieldReadResolver.reads(in: body, scope: scope)
            )
        )
    }
}
