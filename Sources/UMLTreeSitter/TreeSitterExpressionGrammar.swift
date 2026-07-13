@preconcurrency import SwiftTreeSitter
import UMLCore

/// The narrow, per-language adapter body analysis is built on: "is/decompose this one node" —
/// nothing more. A language implements these in terms of its own grammar's real node types, either
/// field-based (e.g. Python's `call { function, arguments }`) or positional (e.g. Kotlin's
/// `call_expression`, which has no fields at all) — both are equally valid implementations of the
/// same seven questions. Every recursive algorithm that *consumes* this adapter — chain-peeling,
/// `CallReceiver` classification, cyclomatic complexity — is shared, generic code in this package.
///
/// Methods that need a node's own text take `source` (`Node` alone has no text — only a byte range
/// into the original source string, which lives on `ParsedSource`).
public protocol TreeSitterExpressionGrammar: Sendable {
    /// Whether a bare call with no explicit receiver (`foo()`) should be classified as an implicit
    /// call on the enclosing instance (`.selfDispatch`, for languages with an implicit `self`/`this`)
    /// or as a free/imported function call (`.free`, e.g. JavaScript, which has no implicit `this`).
    var bareCallIsImplicitSelf: Bool { get }

    /// Decomposes a call expression into its callee (the expression being called — itself decomposed
    /// further, e.g. `self.method`) and its argument expressions. `nil` when `node` is not a call.
    func callParts(of node: Node) -> (callee: Node, arguments: [Node])?

    /// Decomposes a member-access expression (`a.b`) into its object and the accessed member's simple
    /// name. `nil` when `node` is not a member access.
    func memberAccessParts(of node: Node, in source: ParsedSource) -> (object: Node, memberName: String)?

    /// Decomposes an assignment/compound-assignment expression into its target, operator, and
    /// assigned value. `nil` when `node` is not an assignment.
    func assignmentParts(of node: Node) -> (target: Node, op: VariableAssignment.Operator, value: Node)?

    /// Whether `node` is this language's `self`/`this` expression (a keyword node in most grammars;
    /// Python has none — its adapter recognizes the bare identifier text `self`/`cls` instead).
    func isSelfReference(_ node: Node, in source: ParsedSource) -> Bool

    /// Whether `node` is a construction (`Foo()`) rather than a call — a capitalized/known-type
    /// callee, used to populate `Member.referencedTypeNames`.
    func isConstruction(_ node: Node, in source: ParsedSource) -> Bool

    /// Whether `node` is a decision point for cyclomatic complexity (an `if`/`for`/`while`/`case`/
    /// `catch` or a short-circuit `&&`/`||`/ternary).
    func isDecisionPoint(_ node: Node) -> Bool

    /// The identifier text of `node` when it is a bare identifier/name expression; `nil` otherwise.
    func identifierText(of node: Node, in source: ParsedSource) -> String?
}
