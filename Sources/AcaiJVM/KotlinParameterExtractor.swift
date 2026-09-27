import AcaiCore
import AcaiTreeSitter

// MARK: - KotlinParameterExtractor

/// Parses a Kotlin function's value parameters and a class's primary-constructor parameters into
/// `Parameter` values.
struct KotlinParameterExtractor {
    let context: SourceFileContext
    let typeReferences: KotlinTypeReferenceResolver
    let modifiers: KotlinModifiers

    // MARK: - Primary Constructor Parameters

    struct ClassParam {
        let parameter: Parameter
        let isProperty: Bool
        let isReadOnly: Bool
        let accessLevel: AccessLevel
        let modifiers: [Modifier]
        let annotations: [String]
    }

    func primaryConstructorParams(_ node: Node?) -> [ClassParam] {
        guard let node else { return [] }
        let classParamsNode = node.firstChild(withType: "class_parameters") ?? node
        return classParamsNode.allChildren(withType: "class_parameter").map { child in
            let paramModInfo = modifiers.info(fromParentOf: child)
            let binding = modifiers.bindingKind(of: child)
            let isVal = binding == "val"
            let isVar = binding == "var"
            return ClassParam(
                parameter: Parameter(
                    internalName: child.firstChild(withType: "simple_identifier").map { $0.text(in: context) } ?? "",
                    type: typeReferences.extractFirstTypeRef(from: child),
                    defaultValue: defaultValue(of: child)
                ),
                isProperty: isVal || isVar,
                isReadOnly: isVal,
                accessLevel: paramModInfo.accessLevel,
                modifiers: paramModInfo.modifiers,
                annotations: paramModInfo.annotations
            )
        }
    }

    // MARK: - Function Value Parameters

    func functionValueParameters(_ node: Node?) -> [Parameter] {
        guard let node else { return [] }
        return node.allChildren(withType: "parameter").map { child in
            Parameter(
                internalName: child.firstChild(withType: "simple_identifier").map { $0.text(in: context) } ?? "",
                type: typeReferences.extractFirstTypeRef(from: child),
                defaultValue: defaultValue(of: child),
                isVariadic: child.hasAnonymousChild("vararg", in: context)
            )
        }
    }

    /// The first named node after the anonymous `=`, if the parameter carries a default.
    private func defaultValue(of node: Node) -> String? {
        var foundEq = false
        for child in node.children() {
            if !child.isNamed && child.text(in: context) == "=" {
                foundEq = true
                continue
            }
            if foundEq && child.isNamed {
                return child.text(in: context)
            }
        }
        return nil
    }
}
