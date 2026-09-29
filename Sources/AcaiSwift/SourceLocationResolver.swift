import SwiftSyntax
import AcaiCore

/// Resolves a node's line/column against one file's line table. The converter is built once per
/// parse and handed in, because building one walks the whole tree — resolving each location
/// against a fresh converter would cost O(file size) per node.
struct SourceLocationResolver {
    let fileName: String

    private let converter: SourceLocationConverter

    init(fileName: String, converter: SourceLocationConverter) {
        self.fileName = fileName
        self.converter = converter
    }

    func sourceLocation(of node: some SyntaxProtocol) -> AcaiCore.SourceLocation {
        // A tree parsed from source always roots in a SourceFileSyntax; degrade to an unknown
        // location rather than resolve against a converter built for a different tree (e.g. a
        // detached node).
        guard node.root.is(SourceFileSyntax.self) else {
            return AcaiCore.SourceLocation(filePath: fileName, line: 0, column: 0)
        }
        let location = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        return AcaiCore.SourceLocation(
            filePath: fileName,
            line: location.line,
            column: location.column,
            endLine: converter.location(for: node.endPositionBeforeTrailingTrivia).line
        )
    }
}
