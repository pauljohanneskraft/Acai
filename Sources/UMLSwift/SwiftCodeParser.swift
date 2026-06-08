import SwiftSyntax
import SwiftParser
import UMLCore

public struct SwiftCodeParser: CodeParser {
    public let language: CodeArtifact.SourceLanguage = .swift
    public let fileExtensions: [String] = ["swift"]

    public init() {}

    public func parse(source: String, fileName: String) -> CodeArtifact {
        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(fileName: fileName)
        visitor.walk(sourceFile)
        var artifact = visitor.buildArtifact()
        // Surface malformed input rather than silently returning a partial tree.
        artifact.metadata.hasParseErrors = sourceFile.hasError
        return artifact
    }
}
