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

    /// - Parameters:
    ///   - convention: Which markers mark documentation in this language, and how to strip them.
    ///   - commentNodeTypes: The grammar's comment node types — a grammar that gives documentation
    ///     its own node type needs that one listed too.
    ///   - transparentParentTypes: Node types that wrap a declaration without being one (`export …`,
    ///     `template …`): the documentation sits above the wrapper, so the search continues there.
    public init(
        convention: DocumentationComment,
        commentNodeTypes: Set<String> = ["comment"],
        transparentParentTypes: Set<String> = []
    ) {
        self.convention = convention
        self.commentNodeTypes = commentNodeTypes
        self.transparentParentTypes = transparentParentTypes
    }

    /// The prose documenting the declaration `node`, or `nil` when it carries none.
    public func documentation(above node: Node, in context: SourceFileContext) -> String? {
        var comments: [String] = []
        var sibling = node.previousNamedSibling
        while let current = sibling, current.nodeType.map(commentNodeTypes.contains) == true {
            comments.insert(current.text(in: context), at: 0)
            sibling = current.previousNamedSibling
        }
        if let prose = convention.prose(fromLeading: comments) { return prose }

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
