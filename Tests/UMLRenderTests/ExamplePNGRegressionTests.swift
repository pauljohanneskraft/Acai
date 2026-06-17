import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import UMLRender
import UMLCore
import UMLDiagram
@testable import UMLLibrary

/// Structural regression checks for the proof PNGs committed under `Examples/`. Each test asserts
/// the checked-in file exists and is a well-formed PNG, then — when rendering is actually available
/// — re-renders the same diagram and compares image dimensions within a small tolerance.
///
/// Two environment realities are tolerated rather than failed:
/// - **Git LFS pointers.** The PNGs are stored in LFS; a checkout without LFS materialized leaves a
///   short text pointer. We detect that and skip byte-level validation.
/// - **Headless rendering.** `ImageRenderer`/CoreGraphics need a window-server session, so on a
///   headless agent `renderingFailed`/`encodingFailed` are expected; we skip the re-render half.
enum ExamplePNGs {

    /// `Tests/UMLRenderTests/<file>.swift` → repo root is three levels up.
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func examples(_ components: String...) -> URL {
        components.reduce(repoRoot.appendingPathComponent("Examples")) { $0.appendingPathComponent($1) }
    }

    /// True when `data` is a Git LFS pointer file rather than real PNG bytes.
    static func isLFSPointer(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(64), encoding: .utf8) else { return false }
        return prefix.hasPrefix("version https://git-lfs")
    }

    /// The 4-byte PNG signature prefix (`\x89PNG`).
    static func hasPNGMagic(_ data: Data) -> Bool {
        Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47]
    }

    /// Decodes PNG `data` into a `side`×`side` grayscale luminance grid (0–255), squashing aspect
    /// ratio. Both images being compared share dimensions, so the squash is consistent. Returns
    /// `nil` if the image can't be decoded.
    static func luminanceGrid(_ data: Data, side: Int = 96) -> [UInt8]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        var buffer = [UInt8](repeating: 0, count: side * side)
        guard let context = CGContext(
            data: &buffer, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        // Opaque white ground so transparent regions read as background, then draw scaled to fill.
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return buffer
    }

    /// The side of the comparison grid and the per-cell luminance delta (0–255) that counts as a
    /// real change. Downsampling to 256² averages ~300 source pixels per cell, so anti-aliasing /
    /// font drift sinks toward zero while a genuine localized change (an added label, a recoloured
    /// node) still pushes its cells past the delta.
    static let comparisonSide = 256
    static let perCellDelta = 16

    /// The fraction of grid cells whose luminance differs by more than ``perCellDelta``. Measured
    /// separation: re-rendering the same diagram yields 0 changed cells; a stale class render
    /// missing its multiplicity labels yields 5–12; a theme swap or dropped node lights up nearly
    /// all of them. `nil` if either image can't be decoded.
    static func changedCellFraction(_ lhs: Data, _ rhs: Data) -> Double? {
        guard let a = luminanceGrid(lhs, side: comparisonSide),
              let b = luminanceGrid(rhs, side: comparisonSide) else { return nil }
        let changed = zip(a, b).reduce(0) { abs(Int($1.0) - Int($1.1)) > perCellDelta ? $0 + 1 : $0 }
        return Double(changed) / Double(a.count)
    }

    /// The most a committed golden may perceptually differ from a fresh render before it is treated
    /// as stale. Below the smallest observed real change (5 cells ≈ 7.6e-5) and far above the
    /// same-content floor (0), so a content change fails while anti-aliasing drift does not.
    static let maxChangedFraction = 5.0e-5

    /// Reads (width, height) from the IHDR chunk of a PNG: bytes 16..<20 and 20..<24, big-endian.
    static func pngPixelSize(_ data: Data) -> (width: Int, height: Int)? {
        guard data.count >= 24, hasPNGMagic(data) else { return nil }
        let bytes = [UInt8](data)
        func uint32(at offset: Int) -> Int {
            (Int(bytes[offset]) << 24) | (Int(bytes[offset + 1]) << 16)
                | (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
        }
        return (uint32(at: 16), uint32(at: 20))
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

    /// Validates a committed PNG against a freshly-rendered one. `render` mirrors the CLI's
    /// `uml image` code path for that diagram; it may throw a render error on a headless host.
    @MainActor
    static func validate(_ url: URL, render: () throws -> Data) throws {
        let committed = try Data(contentsOf: url)
        #expect(!committed.isEmpty, "\(url.lastPathComponent) is empty")

        if isLFSPointer(committed) { return }  // LFS not materialized — nothing more to check.
        #expect(hasPNGMagic(committed), "\(url.lastPathComponent) is neither a PNG nor an LFS pointer")
        guard let expected = pngPixelSize(committed) else {
            Issue.record("Could not read PNG size from \(url.lastPathComponent)")
            return
        }

        let fresh: Data
        do {
            fresh = try render()
        } catch DiagramImageRenderError.renderingFailed, DiagramImageRenderError.encodingFailed {
            return  // Headless: structural checks above still ran.
        }

        #expect(hasPNGMagic(fresh), "re-rendered \(url.lastPathComponent) is not a PNG")
        guard let actual = pngPixelSize(fresh) else {
            Issue.record("Could not read PNG size from re-rendered \(url.lastPathComponent)")
            return
        }
        // Same renderer/inputs → dimensions match; allow a small tolerance for font/OS drift.
        func close(_ lhs: Int, _ rhs: Int) -> Bool {
            abs(lhs - rhs) <= max(4, Int((Double(rhs) * 0.05).rounded(.up)))
        }
        #expect(
            close(actual.width, expected.width) && close(actual.height, expected.height),
            "\(url.lastPathComponent) size drifted: committed \(expected), re-rendered \(actual)"
        )

        // Content: the committed golden must still match what the current renderer produces. A
        // dimension match alone is blind to in-bounds changes (e.g. multiplicity labels), so this
        // compares the actual pixels via a downsampled, AA-tolerant perceptual diff.
        guard let changed = changedCellFraction(committed, fresh) else {
            Issue.record("Could not compute perceptual diff for \(url.lastPathComponent)")
            return
        }
        let changedCells = Int(changed * 65536)
        #expect(
            changed <= maxChangedFraction,
            "\(url.lastPathComponent) content drifted (\(changedCells) cells); regenerate per Examples/README.md"
        )
    }
}

@Suite("Class diagram PNG exports")
struct ClassDiagramPNGTests {

    // JavaScript is omitted: with no type annotations its class diagram shows only inheritance.
    static let perLanguage: [(stem: String, language: CodeArtifact.SourceLanguage)] = [
        ("swift", .swift), ("kotlin", .kotlin), ("java", .java),
        ("typescript", .typeScript), ("dart", .dart)
    ]

    @Test("per-language class PNG is valid and re-renders to the same size", arguments: perLanguage, ExamplePNGs.themes)
    @MainActor func perLanguageImage(
        _ entry: (stem: String, language: CodeArtifact.SourceLanguage),
        _ theme: (suffix: String, palette: DiagramPalette)
    ) throws {
        try ExamplePNGs.validate(ExamplePNGs.examples("ClassDiagram", "Exports", "\(entry.stem)\(theme.suffix).png")) {
            let artifact = try ExamplePNGs.analyze(ExamplePNGs.examples("ClassDiagram"), languages: [entry.language])
            var configuration = ClassDiagramConfiguration()
            configuration.grouping = .none  // matches `uml image --grouping none`
            return try DiagramImageRenderer.renderPNG(
                artifact: artifact, configuration: configuration,
                language: artifact.standardLanguageConfiguration, scale: 2, palette: theme.palette
            )
        }
    }
}

@Suite("Sequence diagram PNG exports")
struct SequenceDiagramPNGTests {

    static let cases: [(stem: String, language: CodeArtifact.SourceLanguage)] = [
        ("swift", .swift), ("kotlin", .kotlin), ("java", .java), ("typescript", .typeScript), ("dart", .dart)
    ]

    @Test("sequence PNG is valid and re-renders to the same size", arguments: cases, ExamplePNGs.themes)
    @MainActor func image(
        _ entry: (stem: String, language: CodeArtifact.SourceLanguage),
        _ theme: (suffix: String, palette: DiagramPalette)
    ) throws {
        let name = "\(entry.stem)\(theme.suffix).png"
        try ExamplePNGs.validate(ExamplePNGs.examples("SequenceDiagram", "Exports", name)) {
            let artifact = try ExamplePNGs.analyze(ExamplePNGs.examples("SequenceDiagram"), languages: [entry.language])
            let diagram = artifact.sequenceDiagram(
                entryPoint: ("Checkout", "placeOrder"), maxDepth: 5, typeMapping: [:]
            )
            return try DiagramImageRenderer.renderPNG(sequenceDiagram: diagram, scale: 2, palette: theme.palette)
        }
    }
}

@Suite("State diagram PNG exports")
struct StateDiagramPNGTests {

    static let cases: [(stem: String, language: CodeArtifact.SourceLanguage)] = [
        ("swift", .swift), ("kotlin", .kotlin), ("java", .java),
        ("typescript", .typeScript), ("javascript", .javaScript), ("dart", .dart)
    ]

    @Test("state PNG is valid and re-renders to the same size", arguments: cases, ExamplePNGs.themes)
    @MainActor func image(
        _ entry: (stem: String, language: CodeArtifact.SourceLanguage),
        _ theme: (suffix: String, palette: DiagramPalette)
    ) throws {
        try ExamplePNGs.validate(ExamplePNGs.examples("StateDiagram", "Exports", "\(entry.stem)\(theme.suffix).png")) {
            let artifact = try ExamplePNGs.analyze(ExamplePNGs.examples("StateDiagram"), languages: [entry.language])
            let configuration = StateDiagramConfiguration(typeName: "Download", variableName: "state")
            let diagram = try artifact.resolvingExtensions().stateDiagram(configuration: configuration)
            return try DiagramImageRenderer.renderPNG(stateDiagram: diagram, scale: 2, palette: theme.palette)
        }
    }
}

@Suite("Package diagram PNG exports")
struct PackageDiagramPNGTests {

    // `dir` is the on-disk subdirectory; the package sample is scanned per-language subdir.
    static let cases: [(stem: String, dir: String, language: CodeArtifact.SourceLanguage)] = [
        ("swift", "Swift", .swift), ("kotlin", "Kotlin", .kotlin), ("java", "Java", .java),
        ("typescript", "TypeScript", .typeScript), ("dart", "Dart", .dart)
    ]

    @Test("package PNG is valid and re-renders to the same size", arguments: cases, ExamplePNGs.themes)
    @MainActor func image(
        _ entry: (stem: String, dir: String, language: CodeArtifact.SourceLanguage),
        _ theme: (suffix: String, palette: DiagramPalette)
    ) throws {
        let name = "\(entry.stem)\(theme.suffix).png"
        try ExamplePNGs.validate(ExamplePNGs.examples("PackageDiagram", "Exports", name)) {
            let artifact = try ExamplePNGs.analyze(
                ExamplePNGs.examples("PackageDiagram", entry.dir), languages: [entry.language]
            )
            let diagram = artifact.enriched(configuration: artifact.standardLanguageConfiguration)
                .packageDependencyDiagram()
            return try DiagramImageRenderer.renderPNG(packageDiagram: diagram, scale: 2, palette: theme.palette)
        }
    }
}

@Suite("Call graph PNG exports")
struct CallGraphPNGTests {

    static let cases: [(stem: String, dir: String, language: CodeArtifact.SourceLanguage)] = [
        ("swift", "Swift", .swift), ("kotlin", "Kotlin", .kotlin), ("java", "Java", .java),
        ("typescript", "TypeScript", .typeScript), ("dart", "Dart", .dart)
    ]

    @Test("call-graph PNG is valid and re-renders to the same size", arguments: cases, ExamplePNGs.themes)
    @MainActor func image(
        _ entry: (stem: String, dir: String, language: CodeArtifact.SourceLanguage),
        _ theme: (suffix: String, palette: DiagramPalette)
    ) throws {
        try ExamplePNGs.validate(ExamplePNGs.examples("CallGraph", "Exports", "\(entry.stem)\(theme.suffix).png")) {
            let artifact = try ExamplePNGs.analyze(
                ExamplePNGs.examples("CallGraph", entry.dir), languages: [entry.language]
            )
            let graph = artifact.callGraph(scope: .wholeCodebase)
            return try DiagramImageRenderer.renderPNG(callGraph: graph, scale: 2, palette: theme.palette)
        }
    }
}
