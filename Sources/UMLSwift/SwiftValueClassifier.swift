import SwiftSyntax
import UMLCore

/// Classifies Swift expressions into ``VariableAssignment`` values and targets
/// for static state analysis. Shared by `DeclarationVisitor` (assignments inside
/// bodies) and `TypeExtractor` (stored-property initializers).
struct SwiftValueClassifier {

    /// Compound-assignment operators: their result depends on the previous
    /// value, making the assigned state non-enumerable.
    let compoundAssignmentOperators: Set<String> = [
        "+=", "-=", "*=", "/=", "%=",
        "&=", "|=", "^=", "<<=", ">>=",
        "&+=", "&-=", "&*=", "&<<=", "&>>="
    ]

    /// Classifies an assigned (or initializer) expression.
    ///
    /// Enum cases written with payloads (`.loaded(data)`) parse as
    /// `FunctionCallExprSyntax` and are deliberately classified as
    /// `.expression` — their state space is not enumerable.
    func classify(_ expr: ExprSyntax) -> VariableAssignment.Value {
        if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
            let caseName = memberAccess.declName.baseName.text
            if memberAccess.base == nil {
                return .init(kind: .enumCase, text: caseName)
            }
            if let baseName = memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text,
               baseName.first?.isUppercase == true {
                return .init(kind: .enumCase, text: caseName, receiverTypeName: baseName)
            }
            return .init(kind: .expression, text: snippet(expr))
        }
        if expr.is(BooleanLiteralExprSyntax.self) {
            return .init(kind: .booleanLiteral, text: expr.trimmedDescription)
        }
        if expr.is(IntegerLiteralExprSyntax.self) || expr.is(FloatLiteralExprSyntax.self) {
            return .init(kind: .numericLiteral, text: expr.trimmedDescription)
        }
        if let string = expr.as(StringLiteralExprSyntax.self) {
            // Interpolated strings (e.g. "\(x)") depend on runtime values and are
            // not statically enumerable, so they are not fixed states.
            if string.segments.contains(where: { $0.is(ExpressionSegmentSyntax.self) }) {
                return .init(kind: .expression, text: snippet(expr))
            }
            return .init(kind: .stringLiteral, text: expr.trimmedDescription)
        }
        if expr.is(NilLiteralExprSyntax.self) {
            return .init(kind: .nilLiteral, text: "nil")
        }
        return .init(kind: .expression, text: snippet(expr))
    }

    /// Parses an assignment's left-hand side into a target name plus optional
    /// type receiver. Returns `nil` for targets that are not a bare identifier,
    /// a `self.`-qualified property, or a `Type.`-qualified static.
    func target(of expr: ExprSyntax) -> (name: String, receiver: String?)? {
        if let declRef = expr.as(DeclReferenceExprSyntax.self) {
            return (declRef.baseName.text, nil)
        }
        guard let memberAccess = expr.as(MemberAccessExprSyntax.self),
              let baseName = memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text
        else { return nil }
        let name = memberAccess.declName.baseName.text
        if baseName == "self" {
            return (name, nil)
        }
        if baseName.first?.isUppercase == true {
            return (name, baseName)
        }
        return nil
    }

    private func snippet(_ expr: ExprSyntax) -> String {
        let raw = expr.trimmedDescription.replacingOccurrences(of: "\n", with: " ")
        guard raw.count > 80 else { return raw }
        return String(raw.prefix(77)) + "..."
    }
}
