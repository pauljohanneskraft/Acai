import Foundation
import Testing
import UMLCore

// A `CodeParser` may classify a file as a *different* language than the one whose extension
// discovered it (e.g. the C parser owns `.h` but reports `cpp` for a C++ header). `AnalysisService`
// must then label and enrich that file by its *own* `metadata.sourceLanguage`, not the spec's. This
// is an agnostic capability, exercised here with two made-up dialects.

extension CodeArtifact.SourceLanguage {
    fileprivate static let dialectA = CodeArtifact.SourceLanguage(rawValue: "dialectA")
    fileprivate static let dialectB = CodeArtifact.SourceLanguage(rawValue: "dialectB")
}

/// Owns `.dl` and reports `dialectB` for files whose contents begin with `B`, `dialectA` otherwise.
/// Each emitted type has one property of type `Special`.
private struct DualDialectParser: CodeParser {
    var language: CodeArtifact.SourceLanguage { .dialectA }
    var fileExtensions: [String] { ["dl"] }
    // In dialectA, `Special` is a primitive — so it never becomes a structural edge.
    var configuration: LanguageConfiguration { LanguageConfiguration(primitiveTypeNames: ["Special"]) }

    func parse(source: String, fileName: String) -> CodeArtifact {
        let isB = source.hasPrefix("B")
        let name = isB ? "WidgetB" : "WidgetA"
        let widget = TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .public,
            members: [Member(name: "value", kind: .property, accessLevel: .internal,
                             type: TypeReference(name: "Special"))]
        )
        return CodeArtifact(
            metadata: .init(sourceLanguage: isB ? .dialectB : .dialectA, filePaths: [fileName]),
            types: [widget]
        )
    }
}

/// Registers `dialectB`'s configuration (where `Special` is *not* a primitive) so the registry can
/// resolve it. It never collects files of its own in this test.
private struct DialectBParser: CodeParser {
    var language: CodeArtifact.SourceLanguage { .dialectB }
    var fileExtensions: [String] { ["dlb"] }
    var configuration: LanguageConfiguration { LanguageConfiguration() }
    func parse(source: String, fileName: String) -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: .dialectB, filePaths: [fileName]))
    }
}

@Suite("Per-file language routing")
struct PerFileLanguageRoutingTests {

    @Test("each file is enriched with its own detected language's configuration")
    func perFileEnrichment() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("uml-perfile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "A widget".write(to: root.appendingPathComponent("a.dl"), atomically: true, encoding: .utf8)
        try "B widget".write(to: root.appendingPathComponent("b.dl"), atomically: true, encoding: .utf8)

        let service = AnalysisService(parsers: [DualDialectParser(), DialectBParser()])
        let artifact = try service.analyzeProject(at: root, allowedLanguages: [])

        // Only the dialectB file should yield an edge to `Special`: dialectA treats it as a primitive.
        let specialEdges = artifact.relationships.filter { $0.target == "Special" }
        #expect(specialEdges.count == 1)
        #expect(specialEdges.first?.source == "WidgetB")
    }
}
