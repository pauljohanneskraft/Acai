import SwiftSyntax
import SwiftParser
import SwiftDiagnostics
import SwiftParserDiagnostics
import UMLCore

public struct SwiftCodeParser: CodeParser {
    public let language: CodeArtifact.SourceLanguage = .swift
    public let fileExtensions: [String] = ["swift"]

    public init() {}

    public func parse(source: String, fileName: String) -> CodeArtifact {
        let sourceFile = Parser.parse(source: source)
        let typeNameCollector = TypeNameCollector(viewMode: .sourceAccurate)
        typeNameCollector.walk(sourceFile)
        let visitor = DeclarationVisitor(fileName: fileName, knownTypeNames: typeNameCollector.names)
        visitor.walk(sourceFile)
        var artifact = visitor.buildArtifact()
        // Surface malformed input rather than silently returning a partial tree. SwiftSyntax
        // gives human-readable diagnostics with positions, so report them concretely.
        if sourceFile.hasError {
            let converter = SourceLocationConverter(fileName: fileName, tree: sourceFile)
            artifact.metadata.parseDiagnostics = ParseDiagnosticsGenerator
                .diagnostics(for: sourceFile)
                .map { diagnostic in
                    let position = diagnostic.location(converter: converter)
                    return ParseDiagnostic(
                        location: UMLCore.SourceLocation(
                            filePath: fileName, line: position.line, column: position.column
                        ),
                        kind: .error,
                        message: diagnostic.message
                    )
                }
        }
        return artifact
    }
}
