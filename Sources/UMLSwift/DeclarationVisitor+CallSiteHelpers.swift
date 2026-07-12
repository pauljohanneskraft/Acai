import SwiftSyntax
import UMLCore

// Stack management and call-site-resolution helpers — in a separate file so `DeclarationVisitor`'s
// main declaration stays within SwiftLint's `file_length`/`type_body_length`.
extension DeclarationVisitor {

    // MARK: - Stack Management

    var currentNamespace: String? {
        typeStack.last?.qualifiedName
    }

    func pushType(_ type: TypeDeclaration, memberBlock: MemberBlockSyntax) {
        typeStack.append(type)
        methodReturnTypeMapStack.append(returnTypeMap(from: memberBlock))
    }

    func popType() {
        guard let completed = typeStack.popLast() else { return }
        methodReturnTypeMapStack.removeLast()
        if typeStack.isEmpty {
            types.append(completed)
        } else {
            typeStack[typeStack.count - 1].nestedTypes.append(completed)
        }
    }

    /// Builds a `methodName → returnTypeName` map from a type's *direct* member list in one pre-pass
    /// over the raw syntax (not the progressively-accumulated `Member`s), so a forward-declared
    /// method's return type is seen regardless of source order — same rationale as `knownTypeNames`.
    /// Keeps only names with a single, unambiguous return type across all overloads (an overloaded
    /// name with differing return types is dropped rather than guessed).
    func returnTypeMap(from memberBlock: MemberBlockSyntax) -> [String: String] {
        var typesByName: [String: Set<String>] = [:]
        for item in memberBlock.members {
            guard let function = item.decl.as(FunctionDeclSyntax.self),
                  let returnType = function.signature.returnClause?.type.as(IdentifierTypeSyntax.self)
            else { continue }
            typesByName[function.name.text, default: []].insert(returnType.name.text)
        }
        return typesByName.compactMapValues { $0.count == 1 ? $0.first : nil }
    }

    /// Builds a `varName → typeName` map from the stored properties already
    /// extracted for the current type.  Called just before descending into a
    /// function body so we know which receiver names can be resolved.
    ///
    /// When the current type is a protocol extension, also seeds the extended protocol's own
    /// requirement properties (`var x: T { get }`) — the extension's own member list never carries
    /// them (they're declared on the protocol, not the extension), so a default implementation
    /// calling through one (`history.undo()`) would otherwise be unresolvable.
    func buildPropertyMap() -> [String: String] {
        guard let currentType = typeStack.last else { return [:] }
        var map: [String: String] = [:]
        for member in currentType.members where member.kind == .property {
            if let typeName = member.type?.name {
                map[member.name] = typeName
            }
        }
        if currentType.kind == .extension, let extendedProtocol = currentType.extensionOf,
           let requirements = protocolProperties[extendedProtocol] {
            map.merge(requirements) { existing, _ in existing }
        }
        return map
    }

    /// Builds a `paramName → typeName` map from a function/initializer's parameter list, so a
    /// `param.method()` call inside the body resolves. Only parameters with a provable simple type
    /// name are included (mirrors `buildPropertyMap`'s "typed only" bar).
    func parameterMap(from parameterClause: FunctionParameterClauseSyntax) -> [String: String] {
        var map: [String: String] = [:]
        for parameter in signatures.extractParameters(from: parameterClause) {
            if let typeName = parameter.type?.name {
                map[parameter.internalName] = typeName
            }
        }
        return map
    }

    /// `globalName → typeName` for every top-level `let`/`var` with a provable type, built fresh at
    /// each top-level call site so it reflects every global declared so far.
    func topLevelGlobalPropertyMap() -> [String: String] {
        Dictionary(
            globalVariables.compactMap { global in global.type.map { (global.name, $0.name) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Every parameter's internal name, typed or not — unlike `parameterMap`, which only keeps the
    /// typed ones. Seeds `callSiteKnownLocalNames` so an untyped parameter still counts as "known,"
    /// keeping it from being mistaken for an unresolved own-property receiver.
    func knownParameterNames(from parameterClause: FunctionParameterClauseSyntax) -> Set<String> {
        Set(signatures.extractParameters(from: parameterClause).map(\.internalName))
    }

    /// Merges a nested local function's own parameters into `callSiteParameterMap`/
    /// `callSiteKnownLocalNames` for the remainder of the enclosing function's body — so a call
    /// through one of them (`param.method()`) inside the nested function still resolves.
    func mergeNestedFunctionParameters(from parameterClause: FunctionParameterClauseSyntax) {
        for parameter in signatures.extractParameters(from: parameterClause) {
            callSiteKnownLocalNames.insert(parameter.internalName)
            if let typeName = parameter.type?.name {
                callSiteParameterMap[parameter.internalName] = typeName
            }
        }
    }

    /// Records every binding's name into `callSiteKnownLocalNames` immediately (unlike the deferred
    /// type resolution in `pendingLocalBindingsStack`, recording the *name* has no self-shadowing
    /// hazard), and returns the bindings whose type could also be resolved, for the caller to defer.
    func recordingKnownLocalNames(
        from bindings: PatternBindingListSyntax
    ) -> [(name: String, type: String)] {
        let returnTypes = methodReturnTypeMapStack.last ?? [:]
        var newLocals: [(name: String, type: String)] = []
        for binding in bindings {
            if let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                callSiteKnownLocalNames.insert(name)
            }
            if let local = callSites.localBinding(from: binding, methodReturnTypes: returnTypes) {
                newLocals.append(local)
            }
        }
        return newLocals
    }

    /// Call sites gathered from every accessor body of a type-level `var`/`let` declaration, so a
    /// method reached only from a computed property (a SwiftUI `body`, a derived value) is not
    /// mistaken for dead code. Only reached at type scope — `visit` already skips local declarations.
    func collectAccessorCallSites(from node: VariableDeclSyntax) -> [CallSite] {
        guard !typeStack.isEmpty else { return [] }
        let propertyMap = buildPropertyMap()
        var sites: [CallSite] = []
        for binding in node.bindings {
            guard let accessor = binding.accessorBlock else { continue }
            let walker = AccessorCallSiteWalker(
                collector: callSites, propertyMap: propertyMap,
                enclosingTypeName: typeStack.last?.name,
                methodReturnTypes: methodReturnTypeMapStack.last ?? [:], fileName: fileName)
            walker.walk(accessor)
            sites.append(contentsOf: walker.collected)
        }
        return sites
    }
}
