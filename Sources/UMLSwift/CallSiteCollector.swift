import SwiftSyntax
import UMLCore

/// Resolves the body-level facts the sequence/state generators need — call sites, assignments, and
/// referenced type names — from individual expression nodes. Holds no traversal state: the visitor
/// drives the walk and hands each node (plus the current property map) here for interpretation, so
/// all the expression-shape knowledge lives in one place instead of inside the visitor.
struct CallSiteCollector {
    /// Simple names of every type declared in the file, used to recognise `TypeName.method()`
    /// static calls.
    let knownTypeNames: Set<String>

    private let sourceLocations = SourceLocationResolver()
    private let values = SwiftValueClassifier()

    /// A resolvable call site (`receiver.method()`), or `nil` when the receiver can't be resolved to
    /// a known property/type and the call should be dropped. `propertyMap` is the current type's
    /// `storedPropertyName → declaredTypeName` map.
    func callSite(
        from node: FunctionCallExprSyntax, propertyMap: [String: String], fileName: String
    ) -> CallSite? {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) else { return nil }
        let methodName = memberAccess.declName.baseName.text
        guard let resolved = resolveReceiver(
            from: memberAccess.base, propertyMap: propertyMap) else { return nil }
        return CallSite(
            receiverType: resolved.receiverType,
            methodName: methodName,
            location: sourceLocations.sourceLocation(of: node, fileName: fileName)
        )
    }

    /// A variable assignment recovered from a `SequenceExprSyntax`, or `nil` if the sequence is not an
    /// assignment.
    ///
    /// The file is parsed without operator folding, so `x = expr` surfaces as a `SequenceExprSyntax`
    /// whose elements are `[target, AssignmentExpr, value…]`, and compound assignments as
    /// `[target, BinaryOperatorExpr(+=), value…]`.
    func assignment(from node: SequenceExprSyntax, fileName: String) -> VariableAssignment? {
        let elements = Array(node.elements)
        guard elements.count >= 3, let target = values.target(of: elements[0]) else { return nil }

        let op: VariableAssignment.Operator
        if elements[1].is(AssignmentExprSyntax.self) {
            op = .assign
        } else if let binaryOperator = elements[1].as(BinaryOperatorExprSyntax.self),
                  values.compoundAssignmentOperators.contains(binaryOperator.operator.text) {
            op = .compound
        } else {
            return nil
        }

        // Compound results depend on the previous value, so record the whole statement as a
        // non-enumerable expression. For plain assignments, exactly one RHS element is classifiable;
        // longer tails (`a = b ? x : y` folds the ternary into one element, but `a = b = c` does not)
        // are treated as non-enumerable expressions.
        let value: VariableAssignment.Value
        if op == .compound {
            let joined = node.trimmedDescription.replacingOccurrences(of: "\n", with: " ")
            value = .init(kind: .expression, text: String(joined.prefix(80)))
        } else if elements.count == 3 {
            value = values.classify(elements[2])
        } else {
            let joined = elements[2...].map(\.trimmedDescription).joined(separator: " ")
            value = .init(kind: .expression, text: String(joined.prefix(80)))
        }

        return VariableAssignment(
            targetName: target.name,
            targetReceiver: target.receiver,
            op: op,
            value: value,
            location: sourceLocations.sourceLocation(of: node, fileName: fileName)
        )
    }

    /// The capitalised type-like names referenced inside a syntax subtree (constructions, static
    /// access, casts, annotations) — the construction/body dependencies fed to the coupling metrics.
    func referencedTypes(in node: some SyntaxProtocol) -> [String] {
        let collector = TypeReferenceCollector()
        collector.walk(node)
        return Array(collector.names)
    }

    // MARK: - Receiver resolution

    /// A statically-resolved call-site receiver. `receiverType == nil` denotes a call on the
    /// enclosing instance (`self.method()`), which the sequence-diagram generator renders as a
    /// self-message keyed on the caller's type.
    private struct ResolvedReceiver {
        let receiverType: String?
    }

    /// Resolves the declared type for a receiver expression.
    ///
    /// Handles (only when provably resolvable — otherwise returns `nil`, dropping the call):
    /// - `varName.method()` — known stored property → its declared type,
    /// - `self.varName.method()` — strips the leading `self.` then looks up the property,
    /// - `self.method()` — a call on the enclosing instance (`receiverType == nil`),
    /// - `TypeName.method()` — `TypeName` is a known type → a static call.
    private func resolveReceiver(
        from base: ExprSyntax?, propertyMap: [String: String]
    ) -> ResolvedReceiver? {
        guard let base else { return nil }

        if let declRef = base.as(DeclReferenceExprSyntax.self) {
            let name = declRef.baseName.text
            if name == "self" {
                return ResolvedReceiver(receiverType: nil)
            }
            if let propertyType = propertyMap[name] {
                return ResolvedReceiver(receiverType: propertyType)
            }
            if knownTypeNames.contains(name) {
                return ResolvedReceiver(receiverType: name)
            }
            return nil
        }

        if let memberAccess = base.as(MemberAccessExprSyntax.self),
           memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "self",
           let propertyType = propertyMap[memberAccess.declName.baseName.text] {
            return ResolvedReceiver(receiverType: propertyType)
        }

        return nil
    }
}
