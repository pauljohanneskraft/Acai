import SwiftSyntax
import SwiftParser

/// The part of a `Package.swift` that source discovery needs: every source target's declared name,
/// kind and path arguments, read from literal syntax only.
///
/// A manifest that computes any of that — a path built from a variable, targets assembled by a
/// helper or behind an `#if` — leaves ``incompleteReason`` set. Reading half a manifest is worse
/// than not reading it: a target silently missing its sources looks exactly like a small package.
struct SwiftPackageManifest {

    struct Target: Equatable {
        enum Kind {
            case regular
            case test

            /// SwiftPM's predefined directories for the kind, searched in order when the target
            /// declares no `path`.
            var defaultDirectories: [String] {
                switch self {
                case .regular:
                    ["Sources", "Source", "src", "srcs"]
                case .test:
                    ["Tests", "Sources", "Source", "src", "srcs"]
                }
            }

            var flatLayoutDirectories: [String] {
                self == .test ? ["Tests"] : defaultDirectories
            }
        }

        var name: String
        var kind: Kind
        var path: String?
        var exclude: [String]
        /// Subpaths the target restricts itself to; `nil` means the whole target directory.
        var sources: [String]?
        /// Paths declared as `resources:`. SwiftPM copies or processes these rather than compiling
        /// them, so any source file below one belongs to no target.
        var resources: [String]
    }

    private(set) var targets: [Target] = []
    private(set) var incompleteReason: String?

    /// Target kinds that contribute no Swift source of the package's own: prebuilt binaries, system
    /// libraries, and build-tool plugins. Skipping them is not a reason to distrust the manifest.
    private let sourcelessFactories: Set<String> = ["binaryTarget", "systemLibrary", "plugin"]

    init(source: String) {
        read(Parser.parse(source: source))
    }

    private mutating func read(_ file: SourceFileSyntax) {
        let finder = PackageCallFinder(viewMode: .sourceAccurate)
        finder.walk(file)
        guard !finder.changesLayoutAfterInitializer else {
            incompleteReason = "targets or their paths are changed after the Package(...) initializer"
            return
        }
        guard finder.callCount == 1 else {
            incompleteReason = finder.callCount == 0
                ? "no Package(...) initializer found"
                : "more than one Package(...) initializer"
            return
        }
        guard let argument = finder.targetsArgument else {
            incompleteReason = "the Package(...) initializer declares no targets"
            return
        }
        guard let elements = finder.targetElements(of: argument) else {
            incompleteReason = "`targets:` is not a literal array"
            return
        }
        for element in elements {
            read(element)
            if incompleteReason != nil { return }
        }
    }

    private mutating func read(_ element: ExprSyntax) {
        guard let call = element.as(FunctionCallExprSyntax.self),
              let callee = call.calledExpression.as(MemberAccessExprSyntax.self),
              callee.base == nil else {
            incompleteReason = "a target is built by something other than a `.target(…)` call"
            return
        }
        let name = callee.declName.baseName.text
        guard let kind = Target.Kind(targetFactory: name) else {
            if !sourcelessFactories.contains(name) {
                incompleteReason = "unrecognised target kind `.\(name)`"
            }
            return
        }
        guard let target = Target(call: call, kind: kind) else {
            incompleteReason = "a `.\(name)(…)` argument is computed rather than literal"
            return
        }
        targets.append(target)
    }
}

// MARK: - Reading One Target

extension SwiftPackageManifest.Target.Kind {
    init?(targetFactory name: String) {
        switch name {
        case "target", "executableTarget", "macro":
            self = .regular
        case "testTarget":
            self = .test
        default:
            return nil
        }
    }
}

extension SwiftPackageManifest.Target {
    /// Nil when the call names no literal target, or when any argument that matters to discovery is
    /// present but computed.
    init?(call: FunctionCallExprSyntax, kind: Kind) {
        var arguments = LiteralArguments(call.arguments)
        let name = arguments.string("name")
        let path = arguments.string("path")
        let exclude = arguments.strings("exclude")
        let sources = arguments.strings("sources")
        let resources = arguments.resourcePaths("resources")
        guard !arguments.sawComputedValue, let name else { return nil }
        self.init(
            name: name, kind: kind, path: path,
            exclude: exclude ?? [], sources: sources, resources: resources ?? []
        )
    }
}

/// Reads string and `[String]` arguments off a call, recording whether any of the ones asked for was
/// present but not a literal — the signal that the manifest cannot be trusted to describe its own
/// layout.
private struct LiteralArguments {
    private let arguments: LabeledExprListSyntax
    private(set) var sawComputedValue = false

    init(_ arguments: LabeledExprListSyntax) {
        self.arguments = arguments
    }

    mutating func string(_ label: String) -> String? {
        guard let expression = arguments.first(where: { $0.label?.text == label })?.expression else {
            return nil
        }
        guard let value = expression.as(StringLiteralExprSyntax.self)?.literalValue else {
            sawComputedValue = true
            return nil
        }
        return value
    }

    mutating func strings(_ label: String) -> [String]? {
        guard let expression = arguments.first(where: { $0.label?.text == label })?.expression else {
            return nil
        }
        guard let elements = expression.as(ArrayExprSyntax.self)?.elements else {
            sawComputedValue = true
            return nil
        }
        let values = elements.compactMap { $0.expression.as(StringLiteralExprSyntax.self)?.literalValue }
        guard values.count == elements.count else {
            sawComputedValue = true
            return nil
        }
        return values
    }

    /// The paths of a `resources:` array of `.copy`/`.process`/`.embedInCode` rules.
    mutating func resourcePaths(_ label: String) -> [String]? {
        guard let expression = arguments.first(where: { $0.label?.text == label })?.expression else {
            return nil
        }
        guard let elements = expression.as(ArrayExprSyntax.self)?.elements else {
            sawComputedValue = true
            return nil
        }
        let values = elements.compactMap { $0.expression.resourceRulePath }
        guard values.count == elements.count else {
            sawComputedValue = true
            return nil
        }
        return values
    }
}

extension StringLiteralExprSyntax {
    /// The literal's text, or nil when it interpolates or is a multi-segment literal.
    fileprivate var literalValue: String? {
        guard segments.count == 1, case .stringSegment(let segment) = segments.first else { return nil }
        return segment.content.text
    }
}

// MARK: - Locating the Package Initializer

private final class PackageCallFinder: SyntaxVisitor {
    private(set) var targetsArgument: ExprSyntax?
    private(set) var callCount = 0
    /// Immutable file-scope bindings, so `targets: base + extras` can be followed to `let extras = […]`.
    /// `let` only: a `var` may be appended to out of sight of ``changesLayoutAfterInitializer``.
    private(set) var constants: [String: ExprSyntax] = [:]
    /// Set by `package.targets += […]`, `package.targets.append(…)`, `target.path = …` and the like —
    /// but not by `target.swiftSettings = …`, which leaves the layout alone.
    private(set) var changesLayoutAfterInitializer = false

    private let layoutMembers: Set<String> = ["targets", "path", "exclude", "sources"]
    private let mutatingCalls: Set<String> = ["append", "insert", "remove", "removeAll", "removeFirst", "removeLast"]

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.bindingSpecifier.tokenKind == .keyword(.let) else { return .visitChildren }
        for binding in node.bindings {
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  let value = binding.initializer?.value else { continue }
            constants[name] = value
        }
        return .visitChildren
    }

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let elements = Array(node.elements)
        for (index, element) in elements.enumerated().dropFirst() where element.isAssignment {
            if isLayoutMember(elements[index - 1]) { changesLayoutAfterInitializer = true }
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let callee = node.calledExpression.as(MemberAccessExprSyntax.self),
           mutatingCalls.contains(callee.declName.baseName.text),
           let base = callee.base, isLayoutMember(base) {
            changesLayoutAfterInitializer = true
        }
        guard node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Package" else {
            return .visitChildren
        }
        callCount += 1
        targetsArgument = node.arguments.first { $0.label?.text == "targets" }?.expression
        return .skipChildren
    }
}

extension PackageCallFinder {
    /// The target expressions a `targets:` argument stands for: a literal array, a `+` chain of
    /// them, or a same-file `let` bound to either. Nil when any link in the chain is something else,
    /// which leaves the manifest incomplete rather than half-read.
    fileprivate func targetElements(of expression: ExprSyntax, resolved: Set<String> = []) -> [ExprSyntax]? {
        if let array = expression.as(ArrayExprSyntax.self) {
            return array.elements.map(\.expression)
        }
        if let sequence = expression.as(SequenceExprSyntax.self) {
            return concatenation(of: sequence, resolved: resolved)
        }
        guard let name = expression.as(DeclReferenceExprSyntax.self)?.baseName.text,
              !resolved.contains(name), let bound = constants[name] else { return nil }
        return targetElements(of: bound, resolved: resolved.union([name]))
    }

    /// An unfolded `a + b + c`: operands at the even positions, `+` at the odd ones.
    private func concatenation(of sequence: SequenceExprSyntax, resolved: Set<String>) -> [ExprSyntax]? {
        var elements: [ExprSyntax] = []
        for (index, element) in sequence.elements.enumerated() {
            guard index.isMultiple(of: 2) else {
                guard element.as(BinaryOperatorExprSyntax.self)?.operator.text == "+" else { return nil }
                continue
            }
            guard let operand = targetElements(of: element, resolved: resolved) else { return nil }
            elements.append(contentsOf: operand)
        }
        return sequence.elements.count.isMultiple(of: 2) ? nil : elements
    }

    fileprivate func isLayoutMember(_ expression: ExprSyntax) -> Bool {
        guard let access = expression.as(MemberAccessExprSyntax.self), access.base != nil else { return false }
        return layoutMembers.contains(access.declName.baseName.text)
    }
}

extension ExprSyntax {
    /// `=` or a compound assignment such as `+=`, as it appears in an unfolded sequence expression.
    fileprivate var isAssignment: Bool {
        if self.is(AssignmentExprSyntax.self) { return true }
        guard let text = self.as(BinaryOperatorExprSyntax.self)?.operator.text else { return false }
        return text.hasSuffix("=") && !["==", "!=", "<=", ">=", "==="].contains(text)
    }

    /// The literal path of a `.copy("…")`, `.process("…")` or `.embedInCode("…")` resource rule.
    fileprivate var resourceRulePath: String? {
        guard let call = self.as(FunctionCallExprSyntax.self),
              let callee = call.calledExpression.as(MemberAccessExprSyntax.self),
              callee.base == nil,
              ["copy", "process", "embedInCode"].contains(callee.declName.baseName.text),
              let first = call.arguments.first, first.label == nil else { return nil }
        return first.expression.as(StringLiteralExprSyntax.self)?.literalValue
    }
}
