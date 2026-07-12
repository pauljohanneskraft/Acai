import Foundation
import UMLCore
import UMLTreeSitter

// MARK: - Parameters, type annotations & call sites

extension PythonExtractor {

    // MARK: - Parameters

    func extractParameters(_ node: Node) -> [Parameter] {
        var params: [Parameter] = []
        for child in node.namedChildren() {
            switch child.nodeType {
            case "identifier":
                params.append(Parameter(internalName: text(child)))
            case "typed_parameter":
                params.append(extractTypedParameter(child))
            case "default_parameter":
                let name = child.child(byFieldName: "name").map { text($0) } ?? ""
                let def = child.child(byFieldName: "value").map { text($0) }
                params.append(Parameter(internalName: name, defaultValue: def))
            case "typed_default_parameter":
                let name = child.child(byFieldName: "name").map { text($0) } ?? ""
                let type = child.child(byFieldName: "type").flatMap { extractType(fromTypeField: $0) }
                let def = child.child(byFieldName: "value").map { text($0) }
                params.append(Parameter(internalName: name, type: type, defaultValue: def))
            case "list_splat_pattern", "dictionary_splat_pattern":
                params.append(Parameter(internalName: splatName(child), isVariadic: true))
            default:
                break // keyword_separator (`*`), positional_separator (`/`), tuple_pattern
            }
        }
        return params
    }

    private func extractTypedParameter(_ node: Node) -> Parameter {
        // The name is the non-`type` child: a bare identifier, or a `*args`/`**kwargs` splat.
        let nameChild = node.namedChildren().first { $0.nodeType != "type" }
        let isVariadic = nameChild.map {
            $0.nodeType == "list_splat_pattern" || $0.nodeType == "dictionary_splat_pattern"
        } ?? false
        let name = nameChild.map { splatName($0) } ?? ""
        let type = node.child(byFieldName: "type").flatMap { extractType(fromTypeField: $0) }
        return Parameter(internalName: name, type: type, isVariadic: isVariadic)
    }

    /// The inner identifier of a `*args`/`**kwargs` splat, or the identifier's own text.
    private func splatName(_ node: Node) -> String {
        if node.nodeType == "identifier" { return text(node) }
        return node.namedChildren().first { $0.nodeType == "identifier" }.map { text($0) } ?? text(node)
    }

    // MARK: - Type annotations

    /// Wrapper names that carry no type identity of their own — unwrapped to their argument so they
    /// never appear as phantom diagram nodes.
    private static let transparentWrappers: Set<String> = ["Final", "ClassVar", "Annotated"]

    /// Resolves a `type` field node (parameter/return/annotated assignment) to a `TypeReference`.
    func extractType(fromTypeField node: Node) -> TypeReference? {
        let inner = (node.nodeType == "type") ? node.namedChildren().first : node
        return inner.map { typeReference(from: $0) }
    }

    private func typeReference(from node: Node) -> TypeReference {
        switch node.nodeType {
        case "type":
            return node.namedChildren().first.map { typeReference(from: $0) } ?? TypeReference(name: text(node))
        case "identifier":
            return TypeReference(name: text(node))
        case "none":
            return TypeReference(name: "None")
        case "string":
            // Forward reference, e.g. `"User"`.
            return TypeReference(name: text(node).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
        case "attribute", "member_type":
            return TypeReference(name: text(node).components(separatedBy: ".").last ?? text(node))
        case "union_type":
            return unionReference(from: node.namedChildren()
                .filter { $0.nodeType == "type" }
                .map { typeReference(from: $0) })
        case "binary_operator" where binaryOperatorText(node) == "|":
            // PEP 604 union written with the bitwise-or operator, e.g. `str | None`.
            let parts = [node.child(byFieldName: "left"), node.child(byFieldName: "right")]
                .compactMap { $0 }
                .map { typeReference(from: $0) }
            return unionReference(from: parts)
        case "generic_type":
            return genericReference(node)
        case "subscript":
            return subscriptReference(node)
        default:
            return TypeReference(name: text(node))
        }
    }

    private func binaryOperatorText(_ node: Node) -> String {
        node.child(byFieldName: "operator").map { text($0) } ?? ""
    }

    private func genericReference(_ node: Node) -> TypeReference {
        let base = node.namedChildren().first { $0.nodeType == "identifier" }.map { text($0) } ?? text(node)
        var args: [TypeReference] = []
        for param in node.namedChildren() where param.nodeType == "type_parameter" {
            for arg in param.namedChildren() {
                args.append(typeReference(from: arg))
            }
        }
        return composeGeneric(base: base, args: args)
    }

    private func subscriptReference(_ node: Node) -> TypeReference {
        let base = node.child(byFieldName: "value").flatMap { baseTypeName(from: $0) } ?? text(node)
        let args = node.namedChildren().dropFirst().map { typeReference(from: $0) }
        return composeGeneric(base: base, args: Array(args))
    }

    /// Maps a base name + its bracketed arguments to a `TypeReference`, unwrapping the typing
    /// wrappers (`Optional`, `Union`, `Final`, …) that have no type identity of their own.
    private func composeGeneric(base: String, args: [TypeReference]) -> TypeReference {
        switch base {
        case "Optional":
            if var first = args.first {
                first.isOptional = true
                return first
            }
            return TypeReference(name: base)
        case "Union":
            return unionReference(from: args)
        case _ where Self.transparentWrappers.contains(base):
            return args.first ?? TypeReference(name: base)
        default:
            return TypeReference(name: base, genericArguments: args)
        }
    }

    /// Collapses a union (`X | Y | None`, `Union[X, Y]`) to a single reference: a sole `None`
    /// companion marks the type optional; any further members are kept as generic arguments so the
    /// enrichment pass still draws dependency edges to them.
    private func unionReference(from args: [TypeReference]) -> TypeReference {
        let hasNone = args.contains { $0.name == "None" }
        let nonNone = args.filter { $0.name != "None" }
        guard var head = nonNone.first else {
            return TypeReference(name: "None", isOptional: hasNone)
        }
        head.isOptional = head.isOptional || hasNone
        head.genericArguments += Array(nonNone.dropFirst())
        return head
    }

    // MARK: - Call sites

    /// Matches Python `call { function: attribute { object, attribute } }`:
    /// - `self.method(...)` — a call on the enclosing instance (`.selfDispatch`),
    /// - `self.prop.method(...)` — `prop` resolved against the enclosing type's properties,
    /// - `receiver.method(...)` — `receiver` resolved as a known property,
    /// - `TypeName.method(...)` — `TypeName` resolved as a declared type (static call).
    func resolveCallSite(_ node: Node, scope: CallSiteScope) -> CallSite? {
        guard node.nodeType == "call", let funcNode = node.child(byFieldName: "function") else { return nil }

        // Bare call `name(...)` — an implicit receiver. Recorded with no receiver type; the diagram
        // layers resolve it to a top-level function against the whole-artifact view (or drop it,
        // e.g. builtins/constructors), so a call to a free function becomes its own participant.
        if funcNode.nodeType == "identifier" {
            return CallSite(receiver: .free, methodName: text(funcNode), location: loc(node))
        }

        guard funcNode.nodeType == "attribute",
              let attr = funcNode.child(byFieldName: "attribute"),
              let object = funcNode.child(byFieldName: "object") else { return nil }

        let methodName = text(attr)

        if object.nodeType == "identifier", text(object) == "self" {
            return CallSite(receiver: .selfDispatch, methodName: methodName, location: loc(node))
        }

        var receiverName: String?
        if object.nodeType == "identifier" {
            receiverName = text(object)
        } else if object.nodeType == "attribute",
                  let innerObject = object.child(byFieldName: "object"),
                  innerObject.nodeType == "identifier", text(innerObject) == "self",
                  let innerAttr = object.child(byFieldName: "attribute") {
            receiverName = text(innerAttr)
        }

        guard let name = receiverName else { return nil }
        return scope.resolvedCallSite(receiverName: name, methodName: methodName, location: loc(node))
    }

    /// Provable local-variable types: an explicit annotation (`x: Foo = …`), a `Foo()` construction of
    /// a declared type (`x = Foo()`), or a same-type method call with an unambiguous return type —
    /// Python requires an explicit receiver for a method call, so this is `x = self.compute()`, via
    /// `scope.knownMethodReturnTypes` — so `x.method()` resolves to `Foo` (RC4/RC-I). A `self.x = …`
    /// assignment has an `attribute` target, not an `identifier`, so it is left to field synthesis.
    func localBindings(in body: Node, scope: CallSiteScope) -> [String: String] {
        collectLocalBindings(in: body) { node in
            guard node.nodeType == "assignment",
                  let left = node.child(byFieldName: "left"), left.nodeType == "identifier"
            else { return nil }
            let name = text(left)
            if let typeField = node.child(byFieldName: "type"),
               let typeId = typeField.firstChild(withType: "identifier") {
                return (name, text(typeId))
            }
            guard let right = node.child(byFieldName: "right"), right.nodeType == "call",
                  let function = right.child(byFieldName: "function")
            else { return nil }
            if function.nodeType == "identifier", declaredTypeNames.contains(text(function)) {
                return (name, text(function))
            }
            // `x = self.compute()` — Python has no implicit receiver, so a same-type method call
            // always goes through `self.`.
            if function.nodeType == "attribute",
               let object = function.child(byFieldName: "object"), object.nodeType == "identifier",
               text(object) == "self",
               let attr = function.child(byFieldName: "attribute"),
               let returnType = scope.knownMethodReturnTypes[text(attr)] {
                return (name, returnType)
            }
            return nil
        }
    }
}
