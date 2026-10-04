import SwiftSyntax
import AcaiCore

/// Reads the documentation written above a declaration out of its leading trivia.
///
/// Trivia rather than a sibling search: SwiftSyntax hands a declaration the comments above it
/// already attached, and marks which of them are documentation.
struct SwiftDocumentationReader {
    private let convention = DocumentationComment(
        linePrefixes: ["///"], blockOpenings: ["/**"], blockClosing: "*/", continuationMarker: "*"
    )

    func documentation(of node: some SyntaxProtocol) -> String? {
        var comments: [String] = []
        for piece in node.leadingTrivia.reversed() {
            switch piece {
            case .docLineComment(let text), .lineComment(let text),
                 .docBlockComment(let text), .blockComment(let text):
                comments.insert(text, at: 0)
            case .spaces, .tabs, .carriageReturns, .formfeeds, .verticalTabs:
                continue
            case .newlines(let count), .carriageReturnLineFeeds(let count):
                // A blank line ends the run: what sits above it documents something else.
                guard comments.isEmpty || count < 2 else { return convention.prose(fromLeading: comments) }
            default:
                return convention.prose(fromLeading: comments)
            }
        }
        return convention.prose(fromLeading: comments)
    }
}
