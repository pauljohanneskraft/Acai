import SwiftSyntax
import UMLCore

/// Resolves a syntax node's `SourceLocation` (file/line/column) from its position in the parsed tree.
struct SourceLocationResolver {
    func sourceLocation(of node: some SyntaxProtocol, fileName: String) -> UMLCore.SourceLocation {
        let position = node.positionAfterSkippingLeadingTrivia
        // A tree parsed from source always roots in a SourceFileSyntax; degrade to an unknown
        // location rather than crash if that invariant is ever violated (e.g. a detached node).
        guard let sourceFile = node.root.as(SourceFileSyntax.self) else {
            return UMLCore.SourceLocation(filePath: fileName, line: 0, column: 0)
        }
        let converter = SourceLocationConverter(fileName: fileName, tree: sourceFile)
        let location = converter.location(for: position)
        return UMLCore.SourceLocation(
            filePath: fileName,
            line: location.line,
            column: location.column
        )
    }
}
