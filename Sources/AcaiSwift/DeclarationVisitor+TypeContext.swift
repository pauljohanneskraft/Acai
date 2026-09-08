import SwiftSyntax
import AcaiCore

/// Bridges the type/member state `DeclarationVisitor` owns (`typeStack`, `protocolProperties`,
/// `globalVariables`) to the context `CallSiteTracker` (`scope`) needs but doesn't hold itself.
extension DeclarationVisitor {

    // MARK: - Stack Management

    var currentNamespace: String? {
        typeStack.last?.qualifiedName
    }

    func pushType(_ type: TypeDeclaration, memberBlock: MemberBlockSyntax) {
        typeStack.append(type)
        scope.pushTypeScope(memberBlock: memberBlock)
    }

    func popType() {
        guard let completed = typeStack.popLast() else { return }
        scope.popTypeScope()
        if typeStack.isEmpty {
            types.append(completed)
        } else {
            typeStack[typeStack.count - 1].nestedTypes.append(completed)
        }
    }

    /// When the current type is a protocol extension, also seeds the extended protocol's own
    /// requirement properties — the extension's own member list never carries them, so a default
    /// implementation calling through one (`history.undo()`) would otherwise be unresolvable.
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

    func buildArrayElementPropertyMap() -> [String: String] {
        guard let currentType = typeStack.last else { return [:] }
        var map: [String: String] = [:]
        for member in currentType.members where member.kind == .property {
            if let type = member.type, type.isArray, let elementName = type.genericArguments.first?.name {
                map[member.name] = elementName
            }
        }
        return map
    }

    func topLevelGlobalPropertyMap() -> [String: String] {
        Dictionary(
            globalVariables.compactMap { global in global.type.map { (global.name, $0.name) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Attaches every binding's initializer type references (e.g. `= Foo()`) to `members` — the
    /// signature misses these, so this surfaces construction dependencies for the coupling metrics.
    /// Skips accessor bodies (computed getters): a deeply nested `var body: some View { … }` could
    /// recurse far enough to overflow the stack.
    func attachingInitializerReferencedTypes(to members: [Member], from node: VariableDeclSyntax) -> [Member] {
        var referencedSet = Set<String>()
        for binding in node.bindings {
            if let value = binding.initializer?.value {
                referencedSet.formUnion(scope.callSites.referencedTypes(in: value))
            }
        }
        guard !referencedSet.isEmpty else { return members }
        let referenced = Array(referencedSet)
        return members.map { member in
            var copy = member
            copy.referencedTypeNames = referenced
            return copy
        }
    }

    /// Call sites from `node`'s computed-accessor bodies and stored-property initializer expression,
    /// or an empty array outside a type body — a top-level global's initializer is walked separately
    /// by the visitor's own top-level `FunctionCallExprSyntax` handling.
    func collectPropertyCallSites(from node: VariableDeclSyntax) -> [CallSite] {
        guard !typeStack.isEmpty else { return [] }
        let propertyMap = buildPropertyMap()
        let enclosingTypeName = typeStack.last?.name
        return scope.accessorCallSites(
            from: node, propertyMap: propertyMap, enclosingTypeName: enclosingTypeName, fileName: fileName)
            + scope.initializerCallSites(
                from: node, propertyMap: propertyMap, enclosingTypeName: enclosingTypeName, fileName: fileName)
    }
}
