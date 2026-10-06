import AcaiCore

/// Reads the documentation a declaration carries out of the tree around it, following the
/// convention its language actually uses.
///
/// A plugin builds one in `init` from its own ``DocumentationComment`` and its grammar's comment
/// node types, so this names no language.
public struct DocumentationReader: Sendable {
    private let convention: DocumentationComment
    private let commentNodeTypes: Set<String>
    private let transparentParentTypes: Set<String>
    private let skippedSiblingTypes: Set<String>

    /// - Parameters:
    ///   - convention: Which markers mark documentation in this language, and how to strip them.
    ///   - commentNodeTypes: The grammar's comment node types — a grammar that gives documentation
    ///     its own node type needs that one listed too.
    ///   - transparentParentTypes: Node types that wrap a declaration without being one (`export …`,
    ///     `template …`): the documentation sits above the wrapper, so the search continues there.
    ///   - skippedSiblingTypes: Node types belonging to the declaration itself although the grammar
    ///     flattens them into siblings ahead of it (a modifier, a written-out type): the comment run
    ///     is on the far side of them.
    public init(
        convention: DocumentationComment,
        commentNodeTypes: Set<String> = ["comment"],
        transparentParentTypes: Set<String> = [],
        skippedSiblingTypes: Set<String> = []
    ) {
        self.convention = convention
        self.commentNodeTypes = commentNodeTypes
        self.transparentParentTypes = transparentParentTypes
        self.skippedSiblingTypes = skippedSiblingTypes
    }

    /// The prose documenting the declaration `node`, or `nil` when it carries none.
    ///
    /// Only comments directly above the declaration count: a blank line anywhere between them and
    /// it ends the run, so a file header or a comment about something else is never attached.
    public func documentation(above node: Node, in context: SourceFileContext) -> String? {
        var comments: [String] = []
        var below = node
        var sibling = node.previousNamedSibling
        while let current = sibling, let type = current.nodeType, current.lastRow + 1 >= below.firstRow {
            let isComment = commentNodeTypes.contains(type)
            guard isComment || (comments.isEmpty && skippedSiblingTypes.contains(type)) else { break }
            let above = current.previousNamedSibling
            if isComment {
                // A comment sharing a line with the code before it trails that code.
                if let above, above.lastRow == current.firstRow { break }
                comments.append(current.text(in: context))
            }
            below = current
            sibling = above
        }
        if let prose = convention.prose(fromLeading: Array(comments.reversed())) { return prose }

        guard let parent = node.parent, parent.nodeType.map(transparentParentTypes.contains) == true else {
            return nil
        }
        return documentation(above: parent, in: context)
    }

    /// The prose of a string literal that is itself the documentation, as in a language whose
    /// convention puts it inside the declaration's body rather than above it.
    public func documentation(inLiteral node: Node, in context: SourceFileContext) -> String? {
        convention.prose(fromLiteral: node.text(in: context))
    }
}

extension Node {
    fileprivate var firstRow: UInt32 { pointRange.lowerBound.row }

    /// A node whose extent runs to the start of the next line, as some grammars' line comments do,
    /// ends on the line before.
    fileprivate var lastRow: UInt32 {
        let end = pointRange.upperBound
        return end.column == 0 && end.row > firstRow ? end.row - 1 : end.row
    }
}
