import Foundation
import Testing
import UMLCore
import UMLDiagram
import UMLDiff
@testable import UMLLibrary

// Delta (diff) golden-export regression tests, split out of ExampleExportRegressionTests to keep
// each file under the length limit. Each suite mirrors a `uml diff --diagram` code path for one
// diagram type and asserts the regenerated `.delta.dot` / `.delta.mmd` still matches byte-for-byte.

@Suite("Class delta diagram exports", .serialized)
struct ClassDiagramDeltaExportTests {

    /// (golden stem, language, Before/After source folder). Mirrors the class-diagram coverage
    /// (JavaScript omitted — no type annotations). Each language's Before/After shows a change
    /// natural to it: OO languages drop an inheritance and gain a composition; C (no inheritance)
    /// swaps one composition for another.
    static let cases: [(stem: String, language: CodeArtifact.SourceLanguage, folder: String)] = [
        ("swift", .swift, "Swift"),
        ("kotlin", .kotlin, "Kotlin"),
        ("java", .java, "Java"),
        ("typescript", .typeScript, "TypeScript"),
        ("dart", .dart, "Dart"),
        ("python", .python, "Python"),
        ("c", .c, "C"),
        ("cpp", .cpp, "Cpp")
    ]

    /// Mirrors `DiffCommand.deltaDiagram`: analyze both revisions, diff them, then build the union
    /// diagram with the diff-status colour override.
    private func render(
        _ language: CodeArtifact.SourceLanguage, folder: String, mermaid: Bool
    ) throws -> String {
        let old = try ExampleExports.analyze(
            ExampleExports.examples("ClassDiagramDiff", folder, "Before"), language: language)
        let new = try ExampleExports.analyze(
            ExampleExports.examples("ClassDiagramDiff", folder, "After"), language: language)
        let differ = ArtifactDiffer()
        let diff = differ.diff(old: old, new: new)
        let union = differ.unionArtifact(old: old, new: new)
        let options = ClassDiagramOptions(
            showExternalTypes: true,
            languages: new.standardLanguageResolver,
            edgeColorOverride: { rel in DeltaEdgeColors.standard.hex(forStatus: diff.status(of: rel).rawValue) },
            nodeColorOverride: { DeltaEdgeColors.standard.hex(forStatus: diff.status(ofType: $0.id).rawValue) }
        )
        return mermaid
            ? ClassDiagramMermaidRenderer(options: options).generate(from: union)
            : ClassDiagramDOTRenderer(options: options).generate(from: union)
    }

    @Test("regenerated delta DOT matches the checked-in golden", arguments: cases)
    func matchesGolden(stem: String, language: CodeArtifact.SourceLanguage, folder: String) throws {
        let generated = try render(language, folder: folder, mermaid: false)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("ClassDiagramDiff", "Exports", "\(stem).delta.dot")
        )
        #expect(generated == expected, "Delta DOT for \(stem) drifted; regenerate per Examples/README.md")
    }

    @Test("regenerated delta Mermaid matches the checked-in golden", arguments: cases)
    func matchesMermaidGolden(stem: String, language: CodeArtifact.SourceLanguage, folder: String) throws {
        let generated = try render(language, folder: folder, mermaid: true)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("ClassDiagramDiff", "Exports", "\(stem).delta.mmd")
        )
        #expect(generated == expected, "Delta Mermaid for \(stem) drifted; regenerate per Examples/README.md")
    }
}

@Suite("Sequence delta diagram exports", .serialized)
struct SequenceDiagramDeltaExportTests {

    /// One language's sequence-delta case. A struct (not a 4-tuple) to keep both the language's
    /// `dir` and its entry point per case without tripping the large-tuple rule.
    struct Case: Sendable {
        let stem: String
        let language: CodeArtifact.SourceLanguage
        let dir: String
        let entryType: String
        let entryMethod: String
        var entry: (typeName: String, methodName: String) { (entryType, entryMethod) }
    }

    /// Mirrors the sequence coverage (no plain JavaScript). Each Before/After drops one message
    /// (`verify`, red) and adds another (`log`, green); `charge` is unchanged. DOT carries the
    /// colour; Mermaid's sequence syntax can't, so its golden is the union uncolored.
    static let cases: [Case] = [
        Case(stem: "swift", language: .swift, dir: "Swift", entryType: "Checkout", entryMethod: "placeOrder"),
        Case(stem: "kotlin", language: .kotlin, dir: "Kotlin", entryType: "Checkout", entryMethod: "placeOrder"),
        Case(stem: "java", language: .java, dir: "Java", entryType: "Checkout", entryMethod: "placeOrder"),
        Case(stem: "typescript", language: .typeScript, dir: "TypeScript",
             entryType: "Checkout", entryMethod: "placeOrder"),
        Case(stem: "dart", language: .dart, dir: "Dart", entryType: "Checkout", entryMethod: "placeOrder"),
        Case(stem: "python", language: .python, dir: "Python", entryType: "Checkout", entryMethod: "placeOrder"),
        Case(stem: "cpp", language: .cpp, dir: "Cpp", entryType: "Checkout", entryMethod: "placeOrder"),
        Case(stem: "c", language: .c, dir: "C", entryType: "", entryMethod: "place_order")
    ]

    /// Mirrors `DiffCommand.sequenceDelta`: build the sequence diagram from both revisions, diff,
    /// render the union with the per-message colour override (DOT only).
    private func render(_ testCase: Case, mermaid: Bool) throws -> String {
        let old = try ExampleExports.analyze(
            ExampleExports.examples("SequenceDiagramDiff", testCase.dir, "Before"), language: testCase.language)
        let new = try ExampleExports.analyze(
            ExampleExports.examples("SequenceDiagramDiff", testCase.dir, "After"), language: testCase.language)
        let diff = SequenceDiagramDiff(
            old: SequenceDiagramBuilder(entryPoint: testCase.entry).build(from: old),
            new: SequenceDiagramBuilder(entryPoint: testCase.entry).build(from: new))
        if mermaid { return SequenceDiagramMermaidRenderer().render(diff.union) }
        return SequenceDiagramDOTRenderer(
            messageColor: { DeltaEdgeColors.standard.hex(forStatus: diff.status(of: $0).rawValue) }
        ).render(diff.union)
    }

    @Test("regenerated sequence delta DOT matches the checked-in golden", arguments: cases)
    func matchesGolden(_ testCase: Case) throws {
        let generated = try render(testCase, mermaid: false)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("SequenceDiagramDiff", "Exports", "\(testCase.stem).delta.dot"))
        #expect(generated == expected, "Sequence delta DOT for \(testCase.stem) drifted; regenerate per README")
    }

    @Test("regenerated sequence delta Mermaid matches the checked-in golden", arguments: cases)
    func matchesMermaidGolden(_ testCase: Case) throws {
        let generated = try render(testCase, mermaid: true)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("SequenceDiagramDiff", "Exports", "\(testCase.stem).delta.mmd"))
        #expect(generated == expected, "Sequence delta Mermaid for \(testCase.stem) drifted; regenerate per README")
    }
}

@Suite("State delta diagram exports", .serialized)
struct StateDiagramDeltaExportTests {

    /// Every language expresses the same `Download.state` machine (all 9, JS included). `Before`
    /// drops the `verifying` step, so `After` adds `downloading→verifying` and `verifying→finished`
    /// (green) and removes `downloading→finished` (red). DOT carries the colour; Mermaid's state
    /// syntax can't, so its golden is the union uncolored.
    static let cases: [(stem: String, language: CodeArtifact.SourceLanguage, dir: String)] = [
        ("swift", .swift, "Swift"),
        ("kotlin", .kotlin, "Kotlin"),
        ("java", .java, "Java"),
        ("typescript", .typeScript, "TypeScript"),
        ("javascript", .javaScript, "JavaScript"),
        ("dart", .dart, "Dart"),
        ("python", .python, "Python"),
        ("cpp", .cpp, "Cpp"),
        ("c", .c, "C")
    ]

    /// Mirrors `DiffCommand.stateDelta`: build the state diagram from both revisions, diff, render
    /// the union with the per-transition colour override (DOT only).
    private func render(_ language: CodeArtifact.SourceLanguage, dir: String, mermaid: Bool) throws -> String {
        let configuration = StateDiagramConfiguration(typeName: "Download", variableName: "state", maxStates: 20)
        let old = try StateDiagramBuilder(configuration: configuration).build(from: ExampleExports.analyze(
            ExampleExports.examples("StateDiagramDiff", dir, "Before"), language: language).resolvingExtensions())
        let new = try StateDiagramBuilder(configuration: configuration).build(from: ExampleExports.analyze(
            ExampleExports.examples("StateDiagramDiff", dir, "After"), language: language).resolvingExtensions())
        let diff = StateDiagramDiff(old: old, new: new)
        if mermaid { return StateDiagramMermaidRenderer().render(diff.union) }
        return StateDiagramDOTRenderer(
            transitionColor: { DeltaEdgeColors.standard.hex(forStatus: diff.status(of: $0).rawValue) }
        ).render(diff.union)
    }

    @Test("regenerated state delta DOT matches the checked-in golden", arguments: cases)
    func matchesGolden(stem: String, language: CodeArtifact.SourceLanguage, dir: String) throws {
        let generated = try render(language, dir: dir, mermaid: false)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("StateDiagramDiff", "Exports", "\(stem).delta.dot"))
        #expect(generated == expected, "State delta DOT for \(stem) drifted; regenerate per Examples/README.md")
    }

    @Test("regenerated state delta Mermaid matches the checked-in golden", arguments: cases)
    func matchesMermaidGolden(stem: String, language: CodeArtifact.SourceLanguage, dir: String) throws {
        let generated = try render(language, dir: dir, mermaid: true)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("StateDiagramDiff", "Exports", "\(stem).delta.mmd"))
        #expect(generated == expected, "State delta Mermaid for \(stem) drifted; regenerate per Examples/README.md")
    }
}

@Suite("Package delta diagram exports", .serialized)
struct PackageDiagramDeltaExportTests {

    /// Mirrors the package coverage (no JavaScript). `After` adds a new `Reporting` module that
    /// depends on `Core`, so the delta tints the `Reporting` node and the `Reporting→Core` edge
    /// green. Both DOT and Mermaid carry the colour (node fill + edge stroke).
    static let cases: [(stem: String, language: CodeArtifact.SourceLanguage, dir: String)] = [
        ("swift", .swift, "Swift"),
        ("kotlin", .kotlin, "Kotlin"),
        ("java", .java, "Java"),
        ("typescript", .typeScript, "TypeScript"),
        ("dart", .dart, "Dart"),
        ("python", .python, "Python"),
        ("cpp", .cpp, "Cpp"),
        ("c", .c, "C")
    ]

    /// Mirrors `DiffCommand.packageDelta`: build the package diagram from both revisions, diff,
    /// render the union with the per-node and per-edge colour overrides.
    private func render(_ language: CodeArtifact.SourceLanguage, dir: String, mermaid: Bool) throws -> String {
        let oldArtifact = try ExampleExports.analyze(
            ExampleExports.examples("PackageDiagramDiff", dir, "Before"), language: language)
        let newArtifact = try ExampleExports.analyze(
            ExampleExports.examples("PackageDiagramDiff", dir, "After"), language: language)
        let old = PackageDiagramBuilder().build(
            from: oldArtifact.enriched(using: oldArtifact.standardLanguageResolver))
        let new = PackageDiagramBuilder().build(
            from: newArtifact.enriched(using: newArtifact.standardLanguageResolver))
        let diff = PackageDiagramDiff(old: old, new: new)
        let nodeColor: @Sendable (String) -> String? = {
            DeltaEdgeColors.standard.hex(forStatus: diff.status(ofNode: $0).rawValue)
        }
        let edgeColor: @Sendable (String, String) -> String? = {
            DeltaEdgeColors.standard.hex(forStatus: diff.status(ofEdgeFrom: $0, to: $1).rawValue)
        }
        return mermaid
            ? PackageDiagramMermaidRenderer(nodeColor: nodeColor, edgeColor: edgeColor).render(diff.union)
            : PackageDiagramDOTRenderer(nodeColor: nodeColor, edgeColor: edgeColor).render(diff.union)
    }

    @Test("regenerated package delta DOT matches the checked-in golden", arguments: cases)
    func matchesGolden(stem: String, language: CodeArtifact.SourceLanguage, dir: String) throws {
        let generated = try render(language, dir: dir, mermaid: false)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("PackageDiagramDiff", "Exports", "\(stem).delta.dot"))
        #expect(generated == expected, "Package delta DOT for \(stem) drifted; regenerate per Examples/README.md")
    }

    @Test("regenerated package delta Mermaid matches the checked-in golden", arguments: cases)
    func matchesMermaidGolden(stem: String, language: CodeArtifact.SourceLanguage, dir: String) throws {
        let generated = try render(language, dir: dir, mermaid: true)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("PackageDiagramDiff", "Exports", "\(stem).delta.mmd"))
        #expect(generated == expected, "Package delta Mermaid for \(stem) drifted; regenerate per Examples/README.md")
    }
}

@Suite("Call graph delta diagram exports", .serialized)
struct CallGraphDeltaExportTests {

    /// Mirrors the call-graph coverage (no plain JavaScript). `Before` drops the
    /// `OrderService.place → OrderRepository.save` call, so `After` tints that edge and the
    /// `OrderRepository.save` node green. Both DOT and Mermaid carry the colour.
    static let cases: [(stem: String, language: CodeArtifact.SourceLanguage, dir: String)] = [
        ("swift", .swift, "Swift"),
        ("kotlin", .kotlin, "Kotlin"),
        ("java", .java, "Java"),
        ("typescript", .typeScript, "TypeScript"),
        ("dart", .dart, "Dart"),
        ("python", .python, "Python"),
        ("cpp", .cpp, "Cpp"),
        ("c", .c, "C")
    ]

    /// Mirrors `DiffCommand.callGraphDelta`: build the whole-codebase call graph from both
    /// revisions, diff, render the union with the per-node and per-edge colour overrides.
    private func render(_ language: CodeArtifact.SourceLanguage, dir: String, mermaid: Bool) throws -> String {
        let old = try CallGraphBuilder().build(from: ExampleExports.analyze(
            ExampleExports.examples("CallGraphDiff", dir, "Before"), language: language))
        let new = try CallGraphBuilder().build(from: ExampleExports.analyze(
            ExampleExports.examples("CallGraphDiff", dir, "After"), language: language))
        let diff = CallGraphDiff(old: old, new: new)
        let nodeColor: @Sendable (String) -> String? = {
            DeltaEdgeColors.standard.hex(forStatus: diff.status(ofNode: $0).rawValue)
        }
        let edgeColor: @Sendable (String, String) -> String? = {
            DeltaEdgeColors.standard.hex(forStatus: diff.status(ofEdgeFrom: $0, to: $1).rawValue)
        }
        return mermaid
            ? CallGraphMermaidRenderer(nodeColor: nodeColor, edgeColor: edgeColor).render(diff.union)
            : CallGraphDOTRenderer(nodeColor: nodeColor, edgeColor: edgeColor).render(diff.union)
    }

    @Test("regenerated call graph delta DOT matches the checked-in golden", arguments: cases)
    func matchesGolden(stem: String, language: CodeArtifact.SourceLanguage, dir: String) throws {
        let generated = try render(language, dir: dir, mermaid: false)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("CallGraphDiff", "Exports", "\(stem).delta.dot"))
        #expect(generated == expected, "Call graph delta DOT for \(stem) drifted; regenerate per Examples/README.md")
    }

    @Test("regenerated call graph delta Mermaid matches the checked-in golden", arguments: cases)
    func matchesMermaidGolden(stem: String, language: CodeArtifact.SourceLanguage, dir: String) throws {
        let generated = try render(language, dir: dir, mermaid: true)
        let expected = try ExampleExports.golden(
            ExampleExports.examples("CallGraphDiff", "Exports", "\(stem).delta.mmd"))
        #expect(generated == expected, "Call graph delta Mermaid for \(stem) drifted; regenerate per README")
    }
}
