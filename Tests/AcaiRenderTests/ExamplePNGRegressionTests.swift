import CoreGraphics
import Foundation
import Testing
import AcaiPNGComparison
@testable import AcaiRender
import AcaiCore
import AcaiDiagram
@testable import AcaiLibrary

/// Path/pipeline conveniences for the proof PNGs committed under `Examples/`. The actual
/// PNG-comparison math lives in `ExampleGoldenComparator` below, not here.
enum ExamplePNGs {

    /// `Tests/AcaiRenderTests/<file>.swift` → repo root is three levels up.
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func examples(_ components: String...) -> URL {
        components.reduce(repoRoot.appendingPathComponent("Examples")) { $0.appendingPathComponent($1) }
    }

    static func analyze(_ directory: URL, languages: [CodeArtifact.SourceLanguage]) throws -> CodeArtifact {
        try AnalysisService.standard.analyzeProject(at: directory, allowedLanguages: languages)
    }

    /// The committed palettes: each suite is parametrised over these so the same assertions run
    /// for every theme. `suffix` is appended to the file stem (light is the bare `<stem>.png`).
    static let themes: [(suffix: String, palette: DiagramPalette)] = [
        ("", .light),
        (".dark", .dark)
    ]
}

/// Structural + perceptual regression checks for a committed `Examples/` PNG, wrapping
/// `AcaiPNGComparison`'s shared diff math.
///
/// Two environment realities are tolerated rather than failed:
/// - **Git LFS pointers.** The PNGs are stored in LFS; a checkout without LFS materialized leaves a
///   short text pointer, which skips byte-level validation.
/// - **Headless rendering.** `ImageRenderer`/CoreGraphics need a window-server session, so on a
///   headless agent `renderingFailed`/`encodingFailed` skip the re-render half.
struct ExampleGoldenComparator {
    private let comparison = PNGGoldenComparison()

    /// Reads (width, height) from the IHDR chunk of a PNG: bytes 16..<20 and 20..<24, big-endian.
    private func pngPixelSize(_ data: Data) -> (width: Int, height: Int)? {
        guard data.count >= 24, comparison.hasPNGMagic(data) else { return nil }
        let bytes = [UInt8](data)
        func uint32(at offset: Int) -> Int {
            (Int(bytes[offset]) << 24) | (Int(bytes[offset + 1]) << 16)
                | (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
        }
        return (uint32(at: 16), uint32(at: 20))
    }

    /// `render` mirrors the CLI's `acai image` code path for that diagram; it may throw a render
    /// error on a headless host.
    @MainActor
    func validate(_ url: URL, render: () throws -> Data) throws {
        let committed = try Data(contentsOf: url)
        #expect(!committed.isEmpty, "\(url.lastPathComponent) is empty")

        if comparison.isLFSPointer(committed) { return }
        #expect(comparison.hasPNGMagic(committed), "\(url.lastPathComponent) is neither a PNG nor an LFS pointer")
        guard let expected = pngPixelSize(committed) else {
            Issue.record("Could not read PNG size from \(url.lastPathComponent)")
            return
        }

        let fresh: Data
        do {
            fresh = try render()
        } catch DiagramImageRenderError.renderingFailed, DiagramImageRenderError.encodingFailed {
            return
        }

        #expect(comparison.hasPNGMagic(fresh), "re-rendered \(url.lastPathComponent) is not a PNG")
        guard let actual = pngPixelSize(fresh) else {
            Issue.record("Could not read PNG size from re-rendered \(url.lastPathComponent)")
            return
        }
        // Allow a small tolerance for font/OS drift.
        func close(_ lhs: Int, _ rhs: Int) -> Bool {
            abs(lhs - rhs) <= max(4, Int((Double(rhs) * 0.05).rounded(.up)))
        }
        #expect(
            close(actual.width, expected.width) && close(actual.height, expected.height),
            "\(url.lastPathComponent) size drifted: committed \(expected), re-rendered \(actual)"
        )

        // A dimension match alone is blind to in-bounds changes (e.g. multiplicity labels), so this
        // also compares pixels via a downsampled, AA-tolerant perceptual diff.
        switch comparison.compare(committed: committed, rendered: fresh) {
        case .match, .lfsPointer, .notAPNG:
            break
        case .drifted(let changedCells, _):
            Issue.record(
                "\(url.lastPathComponent) content drifted (\(changedCells) cells); regenerate per Examples/README.md"
            )
        case .undecodable:
            Issue.record("Could not compute perceptual diff for \(url.lastPathComponent)")
        }
    }
}

@Suite("Class diagram PNG exports")
struct ClassDiagramPNGTests {
    static let comparator = ExampleGoldenComparator()

    // JavaScript is omitted: with no type annotations its class diagram shows only inheritance.
    static let perLanguage: [(stem: String, language: CodeArtifact.SourceLanguage)] = [
        ("swift", .swift), ("kotlin", .kotlin), ("java", .java),
        ("typescript", .typeScript), ("dart", .dart), ("python", .python),
        ("c", .c), ("cpp", .cpp)
    ]

    @Test("per-language class PNG is valid and re-renders to the same size", arguments: perLanguage, ExamplePNGs.themes)
    @MainActor func perLanguageImage(
        _ entry: (stem: String, language: CodeArtifact.SourceLanguage),
        _ theme: (suffix: String, palette: DiagramPalette)
    ) throws {
        let png = ExamplePNGs.examples("ClassDiagram", "Exports", "\(entry.stem)\(theme.suffix).png")
        try Self.comparator.validate(png) {
            let artifact = try ExamplePNGs.analyze(ExamplePNGs.examples("ClassDiagram"), languages: [entry.language])
            var configuration = ClassDiagramConfiguration()
            configuration.grouping = .none  // matches `acai image --grouping none`
            return try ClassImageRenderer().renderPNG(
                artifact: artifact, configuration: configuration,
                languages: artifact.standardLanguageResolver,
                context: RenderingContext(scale: 2, palette: theme.palette)
            )
        }
    }
}

@Suite("Sequence diagram PNG exports")
struct SequenceDiagramPNGTests {
    static let comparator = ExampleGoldenComparator()

    // OO languages enter on `Checkout.placeOrder`; C has no methods, so it enters on the free
    // function `place_order` (empty type name) and renders the chain as `.control` lifelines.
    static let cases: [(
        stem: String, language: CodeArtifact.SourceLanguage, entry: (typeName: String, methodName: String)
    )] = [
        ("swift", .swift, ("Checkout", "placeOrder")), ("kotlin", .kotlin, ("Checkout", "placeOrder")),
        ("java", .java, ("Checkout", "placeOrder")), ("typescript", .typeScript, ("Checkout", "placeOrder")),
        ("dart", .dart, ("Checkout", "placeOrder")), ("python", .python, ("Checkout", "placeOrder")),
        ("cpp", .cpp, ("Checkout", "placeOrder")), ("c", .c, ("", "place_order"))
    ]

    @Test("sequence PNG is valid and re-renders to the same size", arguments: cases, ExamplePNGs.themes)
    @MainActor func image(
        _ entry: (stem: String, language: CodeArtifact.SourceLanguage, entry: (typeName: String, methodName: String)),
        _ theme: (suffix: String, palette: DiagramPalette)
    ) throws {
        let name = "\(entry.stem)\(theme.suffix).png"
        try Self.comparator.validate(ExamplePNGs.examples("SequenceDiagram", "Exports", name)) {
            let artifact = try ExamplePNGs.analyze(ExamplePNGs.examples("SequenceDiagram"), languages: [entry.language])
            let diagram = SequenceDiagramBuilder(entryPoint: entry.entry, maxDepth: 5, typeMapping: [:])
                .build(from: artifact)
            return try SequenceImageRenderer().renderPNG(
                sequenceDiagram: diagram, context: RenderingContext(scale: 2, palette: theme.palette))
        }
    }
}

@Suite("State diagram PNG exports")
struct StateDiagramPNGTests {
    static let comparator = ExampleGoldenComparator()

    static let cases: [(stem: String, language: CodeArtifact.SourceLanguage)] = [
        ("swift", .swift), ("kotlin", .kotlin), ("java", .java),
        ("typescript", .typeScript), ("javascript", .javaScript), ("dart", .dart), ("python", .python),
        ("cpp", .cpp), ("c", .c)
    ]

    @Test("state PNG is valid and re-renders to the same size", arguments: cases, ExamplePNGs.themes)
    @MainActor func image(
        _ entry: (stem: String, language: CodeArtifact.SourceLanguage),
        _ theme: (suffix: String, palette: DiagramPalette)
    ) throws {
        let png = ExamplePNGs.examples("StateDiagram", "Exports", "\(entry.stem)\(theme.suffix).png")
        try Self.comparator.validate(png) {
            let artifact = try ExamplePNGs.analyze(ExamplePNGs.examples("StateDiagram"), languages: [entry.language])
            let configuration = StateDiagramConfiguration(typeName: "Download", variableName: "state")
            let diagram = try StateDiagramBuilder(configuration: configuration)
                .build(from: artifact.resolvingExtensions())
            return try StateImageRenderer().renderPNG(
                stateDiagram: diagram, context: RenderingContext(scale: 2, palette: theme.palette))
        }
    }
}

@Suite("Package diagram PNG exports")
struct PackageDiagramPNGTests {
    static let comparator = ExampleGoldenComparator()

    static let cases: [(stem: String, dir: String, language: CodeArtifact.SourceLanguage)] = [
        ("swift", "Swift", .swift), ("kotlin", "Kotlin", .kotlin), ("java", "Java", .java),
        ("typescript", "TypeScript", .typeScript), ("dart", "Dart", .dart), ("python", "Python", .python),
        ("c", "C", .c), ("cpp", "Cpp", .cpp)
    ]

    @Test("package PNG is valid and re-renders to the same size", arguments: cases, ExamplePNGs.themes)
    @MainActor func image(
        _ entry: (stem: String, dir: String, language: CodeArtifact.SourceLanguage),
        _ theme: (suffix: String, palette: DiagramPalette)
    ) throws {
        let name = "\(entry.stem)\(theme.suffix).png"
        try Self.comparator.validate(ExamplePNGs.examples("PackageDiagram", "Exports", name)) {
            let artifact = try ExamplePNGs.analyze(
                ExamplePNGs.examples("PackageDiagram", entry.dir), languages: [entry.language]
            )
            let diagram = PackageDiagramBuilder().build(
                from: artifact.enriched(using: artifact.standardLanguageResolver))
            return try PackageImageRenderer().renderPNG(
                packageDiagram: diagram, context: RenderingContext(scale: 2, palette: theme.palette))
        }
    }
}

@Suite("Call graph PNG exports")
struct CallGraphPNGTests {
    static let comparator = ExampleGoldenComparator()

    static let cases: [(stem: String, dir: String, language: CodeArtifact.SourceLanguage)] = [
        ("swift", "Swift", .swift), ("kotlin", "Kotlin", .kotlin), ("java", "Java", .java),
        ("typescript", "TypeScript", .typeScript), ("dart", "Dart", .dart), ("python", "Python", .python),
        ("c", "C", .c), ("cpp", "Cpp", .cpp)
    ]

    @Test("call-graph PNG is valid and re-renders to the same size", arguments: cases, ExamplePNGs.themes)
    @MainActor func image(
        _ entry: (stem: String, dir: String, language: CodeArtifact.SourceLanguage),
        _ theme: (suffix: String, palette: DiagramPalette)
    ) throws {
        let png = ExamplePNGs.examples("CallGraph", "Exports", "\(entry.stem)\(theme.suffix).png")
        try Self.comparator.validate(png) {
            let artifact = try ExamplePNGs.analyze(
                ExamplePNGs.examples("CallGraph", entry.dir), languages: [entry.language]
            )
            let graph = CallGraphBuilder(scope: .wholeCodebase).build(from: artifact)
            return try CallGraphImageRenderer().renderPNG(
                callGraph: graph, context: RenderingContext(scale: 2, palette: theme.palette))
        }
    }
}
