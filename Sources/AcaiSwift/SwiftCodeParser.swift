import SwiftSyntax
import SwiftParser
import SwiftDiagnostics
import SwiftParserDiagnostics
import AcaiCore

public struct SwiftCodeParser: CodeParser {
    public let language: CodeArtifact.SourceLanguage = .swift
    public let fileExtensions: [String] = ["swift"]

    public init() {}

    public func parse(source: String, fileName: String) -> CodeArtifact {
        parse(source: source, fileName: fileName) { SourceLocationConverter(fileName: $0, tree: $1) }
    }

    /// `makeConverter` is the seam a test counts through: building a converter walks the whole tree,
    /// so exactly one is built per file and shared by every location lookup and the diagnostics pass.
    func parse(
        source: String, fileName: String,
        makeConverter: (String, SourceFileSyntax) -> SourceLocationConverter
    ) -> CodeArtifact {
        let sourceFile = Parser.parse(source: source)
        let converter = makeConverter(fileName, sourceFile)
        let sourceLocations = SourceLocationResolver(fileName: fileName, converter: converter)
        let typeNameCollector = TypeNameCollector(viewMode: .sourceAccurate)
        typeNameCollector.walk(sourceFile)
        let protocolPropertyCollector = ProtocolPropertyCollector(viewMode: .sourceAccurate)
        protocolPropertyCollector.walk(sourceFile)
        let visitor = DeclarationVisitor(
            sourceLocations: sourceLocations, knownTypeNames: typeNameCollector.names,
            protocolProperties: protocolPropertyCollector.propertiesByProtocol)
        visitor.walk(sourceFile)
        var artifact = visitor.buildArtifact()
        // Surface malformed input rather than silently returning a partial tree.
        if sourceFile.hasError {
            artifact.metadata.parseDiagnostics = ParseDiagnosticsGenerator
                .diagnostics(for: sourceFile)
                .map { diagnostic in
                    let position = diagnostic.location(converter: converter)
                    return ParseDiagnostic(
                        location: AcaiCore.SourceLocation(
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
