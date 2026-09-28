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
            case plugin

            /// SwiftPM's predefined directories for the kind, searched in order when the target
            /// declares no `path`.
            var defaultDirectories: [String] {
                switch self {
                case .regular:
                    ["Sources", "Source", "src", "srcs"]
                case .test:
                    ["Tests", "Sources", "Source", "src", "srcs"]
                case .plugin:
                    ["Plugins"]
                }
            }
        }

        var name: String
        var kind: Kind
        var path: String?
        var exclude: [String]
        /// Subpaths the target restricts itself to; `nil` means the whole target directory.
        var sources: [String]?
    }

    private(set) var targets: [Target] = []
    private(set) var incompleteReason: String?

    init(source: String) {
        read(Parser.parse(source: source))
    }

    private mutating func read(_ file: SourceFileSyntax) {
        let finder = PackageCallFinder(viewMode: .sourceAccurate)
        finder.walk(file)
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
        guard let elements = argument.as(ArrayExprSyntax.self)?.elements else {
            incompleteReason = "`targets:` is not a literal array"
            return
        }
        for element in elements {
            read(element.expression)
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
            // `binaryTarget` and `systemLibrary` have no sources of their own to parse.
            if name != "binaryTarget", name != "systemLibrary" {
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
        case "plugin":
            self = .plugin
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
        guard !arguments.sawComputedValue, let name else { return nil }
        self.init(name: name, kind: kind, path: path, exclude: exclude ?? [], sources: sources)
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

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Package" else {
            return .visitChildren
        }
        callCount += 1
        targetsArgument = node.arguments.first { $0.label?.text == "targets" }?.expression
        return .skipChildren
    }
}
