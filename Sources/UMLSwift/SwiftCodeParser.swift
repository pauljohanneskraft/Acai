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
        return visitor.buildArtifact()
    }
}
