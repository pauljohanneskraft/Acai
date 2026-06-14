import Foundation
import Testing
import UMLCore
import UMLDiagram
@testable import UMLLibrary

/// Regression tests that re-derive every checked-in DOT export under `Examples/` from its
/// sample sources and assert the output still matches byte-for-byte. Each case mirrors the
/// exact code path the `uml diagram` CLI uses, so a drift here means either a real regression
/// or an intentional output change — in which case regenerate the goldens with the commands
/// documented in `Examples/README.md`.
///
/// Cross-platform on purpose: this target avoids `UMLRender`, so the DOT goldens are exercised
/// on Linux too. The proof PNGs are validated separately (macOS-only) in `UMLRenderTests`.
enum ExampleExports {

    /// `Tests/UMLExamplesTests/<file>.swift` → repo root is three levels up.
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func examples(_ components: String...) -> URL {
        components.reduce(repoRoot.appendingPathComponent("Examples")) { $0.appendingPathComponent($1) }
    }

    /// Reads a golden file, failing with a clear message if it is missing.
    static func golden(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    static func analyze(_ directory: URL, language: CodeArtifact.SourceLanguage) throws -> CodeArtifact {
        try AnalysisService.shared.analyzeProject(at: directory, allowedLanguages: [language])
    }
}

@Suite("Class diagram DOT exports", .serialized)
struct ClassDiagramExportTests {

    /// (golden file stem, language) for every language the class-diagram sample covers.
    /// JavaScript is intentionally absent: with no type annotations its class diagram shows
    /// only inheritance, so it isn't a useful class example (it still appears in StateDiagram).
    static let cases: [(stem: String, language: CodeArtifact.SourceLanguage)] = [
        ("swift", .swift),
        ("kotlin", .kotlin),
        ("java", .java),
        ("typescript", .typeScript),
        ("dart", .dart)
    ]

    @Test("regenerated class DOT matches the checked-in golden", arguments: cases)
    func matchesGolden(stem: String, language: CodeArtifact.SourceLanguage) throws {
        let artifact = try ExampleExports.analyze(
            ExampleExports.examples("ClassDiagram"), language: language
        )
        // Mirrors DiagramCommand.renderClassDOT with default options.
        let generated = DOTGenerator(options: ClassDiagramOptions()).generate(from: artifact)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("ClassDiagram", "Exports", "\(stem).dot")
        )
        #expect(generated == expected, "Class DOT for \(stem) drifted; regenerate per Examples/README.md")
    }

    @Test("regenerated class Mermaid matches the checked-in golden", arguments: cases)
    func matchesMermaidGolden(stem: String, language: CodeArtifact.SourceLanguage) throws {
        let artifact = try ExampleExports.analyze(
            ExampleExports.examples("ClassDiagram"), language: language
        )
        // Mirrors DiagramCommand.renderClass with `--format mermaid` and default options.
        let generated = ClassDiagramMermaidRenderer(options: ClassDiagramOptions()).generate(from: artifact)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("ClassDiagram", "Exports", "\(stem).mmd")
        )
        #expect(generated == expected, "Class Mermaid for \(stem) drifted; regenerate per Examples/README.md")
    }
}

@Suite("Sequence diagram DOT exports", .serialized)
struct SequenceDiagramExportTests {

    /// Sequence tracing needs typed receivers, which Dart and plain JavaScript lack — so the
    /// sample (and these goldens) cover the four languages that populate `callSites` with types.
    static let cases: [(stem: String, language: CodeArtifact.SourceLanguage)] = [
        ("swift", .swift),
        ("kotlin", .kotlin),
        ("java", .java),
        ("typescript", .typeScript)
    ]

    @Test("regenerated sequence DOT matches the checked-in golden", arguments: cases)
    func matchesGolden(stem: String, language: CodeArtifact.SourceLanguage) throws {
        let artifact = try ExampleExports.analyze(
            ExampleExports.examples("SequenceDiagram"), language: language
        )
        // Mirrors DiagramCommand.renderSequenceDOT for `Checkout.placeOrder` with defaults.
        let diagram = artifact.sequenceDiagram(
            entryPoint: ("Checkout", "placeOrder"), maxDepth: 5, typeMapping: [:]
        )
        #expect(!diagram.participants.isEmpty, "\(stem) sequence trace produced no participants")
        let generated = SequenceDiagramDOTRenderer().render(diagram)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("SequenceDiagram", "Exports", "\(stem).dot")
        )
        #expect(generated == expected, "Sequence DOT for \(stem) drifted; regenerate per Examples/README.md")
    }

    @Test("regenerated sequence Mermaid matches the checked-in golden", arguments: cases)
    func matchesMermaidGolden(stem: String, language: CodeArtifact.SourceLanguage) throws {
        let artifact = try ExampleExports.analyze(
            ExampleExports.examples("SequenceDiagram"), language: language
        )
        let diagram = artifact.sequenceDiagram(
            entryPoint: ("Checkout", "placeOrder"), maxDepth: 5, typeMapping: [:]
        )
        #expect(!diagram.participants.isEmpty, "\(stem) sequence trace produced no participants")
        let generated = SequenceDiagramMermaidRenderer().render(diagram)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("SequenceDiagram", "Exports", "\(stem).mmd")
        )
        #expect(generated == expected, "Sequence Mermaid for \(stem) drifted; regenerate per Examples/README.md")
    }
}

@Suite("State diagram DOT exports", .serialized)
struct StateDiagramExportTests {

    /// All six languages express the same `Download.state` machine, so the state-from spec
    /// is uniform; only the parser under test differs.
    static let cases: [(stem: String, language: CodeArtifact.SourceLanguage)] = [
        ("swift", .swift),
        ("kotlin", .kotlin),
        ("java", .java),
        ("typescript", .typeScript),
        ("javascript", .javaScript),
        ("dart", .dart)
    ]

    @Test("regenerated state DOT matches the checked-in golden", arguments: cases)
    func matchesGolden(stem: String, language: CodeArtifact.SourceLanguage) throws {
        let artifact = try ExampleExports.analyze(
            ExampleExports.examples("StateDiagram"), language: language
        )
        // Mirrors DiagramCommand.renderStateDOT (resolvingExtensions + default maxStates/theme).
        let configuration = StateDiagramConfiguration(typeName: "Download", variableName: "state")
        let diagram = try artifact.resolvingExtensions().stateDiagram(configuration: configuration)
        let generated = StateDiagramDOTRenderer().render(diagram)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("StateDiagram", "Exports", "\(stem).dot")
        )
        #expect(generated == expected, "State DOT for \(stem) drifted; regenerate per Examples/README.md")
    }

    @Test("regenerated state Mermaid matches the checked-in golden", arguments: cases)
    func matchesMermaidGolden(stem: String, language: CodeArtifact.SourceLanguage) throws {
        let artifact = try ExampleExports.analyze(
            ExampleExports.examples("StateDiagram"), language: language
        )
        let configuration = StateDiagramConfiguration(typeName: "Download", variableName: "state")
        let diagram = try artifact.resolvingExtensions().stateDiagram(configuration: configuration)
        let generated = StateDiagramMermaidRenderer().render(diagram)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("StateDiagram", "Exports", "\(stem).mmd")
        )
        #expect(generated == expected, "State Mermaid for \(stem) drifted; regenerate per Examples/README.md")
    }
}
