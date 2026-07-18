import Foundation
import Testing
import AcaiCore
import AcaiDiagram
@testable import AcaiLibrary

/// Regression tests that re-derive every checked-in DOT export under `Examples/` from its
/// sample sources and assert the output still matches byte-for-byte. Each case mirrors the
/// exact code path the `acai diagram` CLI uses, so a drift here means either a real regression
/// or an intentional output change — in which case regenerate the goldens with the commands
/// documented in `Examples/README.md`.
///
/// Cross-platform on purpose: this target avoids `AcaiRender`, so the DOT goldens are exercised
/// on Linux too. The proof PNGs are validated separately (macOS-only) in `AcaiRenderTests`.
enum ExampleExports {

    /// `Tests/AcaiExamplesTests/<file>.swift` → repo root is three levels up.
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
        try AnalysisService.standard.analyzeProject(at: directory, allowedLanguages: [language])
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
        ("dart", .dart),
        ("python", .python),
        ("c", .c),
        ("cpp", .cpp)
    ]

    @Test("regenerated class DOT matches the checked-in golden", arguments: cases)
    func matchesGolden(stem: String, language: CodeArtifact.SourceLanguage) throws {
        let artifact = try ExampleExports.analyze(
            ExampleExports.examples("ClassDiagram"), language: language
        )
        // Mirrors DiagramCommand.renderClassDOT with default options.
        let options = ClassDiagramOptions(languages: artifact.standardLanguageResolver)
        let generated = ClassDiagramDOTRenderer(options: options).generate(from: artifact)
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
        let options = ClassDiagramOptions(languages: artifact.standardLanguageResolver)
        let generated = ClassDiagramMermaidRenderer(options: options).generate(from: artifact)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("ClassDiagram", "Exports", "\(stem).mmd")
        )
        #expect(generated == expected, "Class Mermaid for \(stem) drifted; regenerate per Examples/README.md")
    }
}

@Suite("Sequence diagram DOT exports", .serialized)
struct SequenceDiagramExportTests {

    /// Sequence tracing needs callable receivers. Plain JavaScript carries none, so it stays out;
    /// the other languages populate `callSites`. The OO languages enter on the `Checkout.placeOrder`
    /// method; C has no methods, so it enters on the free function `place_order` (empty type name)
    /// and renders the same call chain as `.control` lifelines.
    static let cases: [(
        stem: String, language: CodeArtifact.SourceLanguage, entry: (typeName: String, methodName: String)
    )] = [
        ("swift", .swift, ("Checkout", "placeOrder")),
        ("kotlin", .kotlin, ("Checkout", "placeOrder")),
        ("java", .java, ("Checkout", "placeOrder")),
        ("typescript", .typeScript, ("Checkout", "placeOrder")),
        ("dart", .dart, ("Checkout", "placeOrder")),
        ("python", .python, ("Checkout", "placeOrder")),
        ("cpp", .cpp, ("Checkout", "placeOrder")),
        ("c", .c, ("", "place_order"))
    ]

    @Test("regenerated sequence DOT matches the checked-in golden", arguments: cases)
    func matchesGolden(
        stem: String, language: CodeArtifact.SourceLanguage, entry: (typeName: String, methodName: String)
    ) throws {
        let artifact = try ExampleExports.analyze(
            ExampleExports.examples("SequenceDiagram"), language: language
        )
        // Mirrors DiagramCommand.renderSequenceDOT for the language's entry point with defaults.
        let diagram = SequenceDiagramBuilder(entryPoint: entry, maxDepth: 5, typeMapping: [:]).build(from: artifact)
        #expect(!diagram.participants.isEmpty, "\(stem) sequence trace produced no participants")
        let generated = SequenceDiagramDOTRenderer().render(diagram)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("SequenceDiagram", "Exports", "\(stem).dot")
        )
        #expect(generated == expected, "Sequence DOT for \(stem) drifted; regenerate per Examples/README.md")
    }

    @Test("regenerated sequence Mermaid matches the checked-in golden", arguments: cases)
    func matchesMermaidGolden(
        stem: String, language: CodeArtifact.SourceLanguage, entry: (typeName: String, methodName: String)
    ) throws {
        let artifact = try ExampleExports.analyze(
            ExampleExports.examples("SequenceDiagram"), language: language
        )
        let diagram = SequenceDiagramBuilder(entryPoint: entry, maxDepth: 5, typeMapping: [:]).build(from: artifact)
        #expect(!diagram.participants.isEmpty, "\(stem) sequence trace produced no participants")
        let generated = SequenceDiagramMermaidRenderer().render(diagram)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("SequenceDiagram", "Exports", "\(stem).mmd")
        )
        #expect(generated == expected, "Sequence Mermaid for \(stem) drifted; regenerate per Examples/README.md")
    }
}

@Suite("Package diagram DOT exports", .serialized)
struct PackageDiagramExportTests {

    /// The package sample is multi-module by directory (`Core` and `Banking`), so unlike the
    /// other examples it is scanned per-language **subdirectory** — scanning the parent would
    /// fold every module under a single `Swift`/`Kotlin` group. Each language expresses the same
    /// two-module model (per-parser metric nuances aside, e.g. Dart abstractness).
    /// `dir` is the on-disk subdirectory (`TypeScript` is camel-cased, so it can't be derived
    /// from `stem` via `capitalized`).
    static let cases: [(stem: String, dir: String, language: CodeArtifact.SourceLanguage)] = [
        ("swift", "Swift", .swift),
        ("kotlin", "Kotlin", .kotlin),
        ("java", "Java", .java),
        ("typescript", "TypeScript", .typeScript),
        ("dart", "Dart", .dart),
        ("python", "Python", .python),
        ("c", "C", .c),
        ("cpp", "Cpp", .cpp)
    ]

    @Test("regenerated package DOT matches the checked-in golden", arguments: cases)
    func matchesGolden(stem: String, dir: String, language: CodeArtifact.SourceLanguage) throws {
        let artifact = try ExampleExports.analyze(
            ExampleExports.examples("PackageDiagram", dir), language: language
        )
        // Mirrors DiagramCommand.renderPackage (enriched + default theme/font).
        let diagram = PackageDiagramBuilder().build(
            from: artifact.enriched(using: artifact.standardLanguageResolver))
        #expect(diagram.nodes.count == 2, "\(stem) package diagram should have Core + Banking modules")
        let generated = PackageDiagramDOTRenderer().render(diagram)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("PackageDiagram", "Exports", "\(stem).dot")
        )
        #expect(generated == expected, "Package DOT for \(stem) drifted; regenerate per Examples/README.md")
    }

    @Test("regenerated package Mermaid matches the checked-in golden", arguments: cases)
    func matchesMermaidGolden(stem: String, dir: String, language: CodeArtifact.SourceLanguage) throws {
        let artifact = try ExampleExports.analyze(
            ExampleExports.examples("PackageDiagram", dir), language: language
        )
        let diagram = PackageDiagramBuilder().build(
            from: artifact.enriched(using: artifact.standardLanguageResolver))
        let generated = PackageDiagramMermaidRenderer().render(diagram)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("PackageDiagram", "Exports", "\(stem).mmd")
        )
        #expect(generated == expected, "Package Mermaid for \(stem) drifted; regenerate per Examples/README.md")
    }
}

@Suite("Call graph DOT exports", .serialized)
struct CallGraphExportTests {

    /// The call-graph sample (an order-submission fan-out) carries typed call receivers in
    /// every language, so the resolved graph is identical bar the parser under test. JavaScript
    /// is omitted (no typed receivers), as it is for the sequence diagram.
    /// `dir` is the on-disk subdirectory (`TypeScript` is camel-cased).
    static let cases: [(stem: String, dir: String, language: CodeArtifact.SourceLanguage)] = [
        ("swift", "Swift", .swift),
        ("kotlin", "Kotlin", .kotlin),
        ("java", "Java", .java),
        ("typescript", "TypeScript", .typeScript),
        ("dart", "Dart", .dart),
        ("python", "Python", .python),
        ("c", "C", .c),
        ("cpp", "Cpp", .cpp)
    ]

    @Test("regenerated call-graph DOT matches the checked-in golden", arguments: cases)
    func matchesGolden(stem: String, dir: String, language: CodeArtifact.SourceLanguage) throws {
        let artifact = try ExampleExports.analyze(
            ExampleExports.examples("CallGraph", dir), language: language
        )
        // Mirrors DiagramCommand.callGraphExport (whole-codebase scope, default title/theme).
        let graph = CallGraphBuilder(scope: .wholeCodebase, title: "Call graph").build(from: artifact)
        #expect(!graph.edges.isEmpty, "\(stem) call graph produced no edges")
        let generated = CallGraphDOTRenderer().render(graph)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("CallGraph", "Exports", "\(stem).dot")
        )
        #expect(generated == expected, "Call-graph DOT for \(stem) drifted; regenerate per Examples/README.md")
    }

    @Test("regenerated call-graph Mermaid matches the checked-in golden", arguments: cases)
    func matchesMermaidGolden(stem: String, dir: String, language: CodeArtifact.SourceLanguage) throws {
        let artifact = try ExampleExports.analyze(
            ExampleExports.examples("CallGraph", dir), language: language
        )
        let graph = CallGraphBuilder(scope: .wholeCodebase, title: "Call graph").build(from: artifact)
        let generated = CallGraphMermaidRenderer().render(graph)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("CallGraph", "Exports", "\(stem).mmd")
        )
        #expect(generated == expected, "Call-graph Mermaid for \(stem) drifted; regenerate per Examples/README.md")
    }
}

@Suite("State diagram DOT exports", .serialized)
struct StateDiagramExportTests {

    /// Every language expresses the same `Download.state` machine, so the state-from spec is
    /// uniform; only the parser under test differs. C has no methods, so its transitions live in
    /// free functions that mutate the struct by pointer (`d->state = …`); the value-flow analysis
    /// attributes those writes to `Download` by receiver type.
    static let cases: [(stem: String, language: CodeArtifact.SourceLanguage)] = [
        ("swift", .swift),
        ("kotlin", .kotlin),
        ("java", .java),
        ("typescript", .typeScript),
        ("javascript", .javaScript),
        ("dart", .dart),
        ("python", .python),
        ("cpp", .cpp),
        ("c", .c)
    ]

    @Test("regenerated state DOT matches the checked-in golden", arguments: cases)
    func matchesGolden(stem: String, language: CodeArtifact.SourceLanguage) throws {
        let artifact = try ExampleExports.analyze(
            ExampleExports.examples("StateDiagram"), language: language
        )
        // Mirrors DiagramCommand.renderStateDOT (resolvingExtensions + default maxStates/theme).
        let configuration = StateDiagramConfiguration(typeName: "Download", variableName: "state")
        let diagram = try StateDiagramBuilder(configuration: configuration).build(from: artifact.resolvingExtensions())
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
        let diagram = try StateDiagramBuilder(configuration: configuration).build(from: artifact.resolvingExtensions())
        let generated = StateDiagramMermaidRenderer().render(diagram)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("StateDiagram", "Exports", "\(stem).mmd")
        )
        #expect(generated == expected, "State Mermaid for \(stem) drifted; regenerate per Examples/README.md")
    }
}
