import Foundation
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
        try AnalysisService.shared.analyzeProject(at: directory, allowedLanguages: languages)
    }

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
    }
}

@Suite("Class diagram PNG exports")
struct ClassDiagramPNGTests {

    // JavaScript is omitted: with no type annotations its class diagram shows only inheritance.
    static let perLanguage: [(stem: String, language: CodeArtifact.SourceLanguage)] = [
        ("swift", .swift), ("kotlin", .kotlin), ("java", .java),
        ("typescript", .typeScript), ("dart", .dart)
    ]

    @Test("per-language class PNG is valid and re-renders to the same size", arguments: perLanguage)
    @MainActor func perLanguageImage(stem: String, language: CodeArtifact.SourceLanguage) throws {
        try ExamplePNGs.validate(ExamplePNGs.examples("ClassDiagram", "Exports", "\(stem).png")) {
            let artifact = try ExamplePNGs.analyze(ExamplePNGs.examples("ClassDiagram"), languages: [language])
            var configuration = ClassDiagramConfiguration()
            configuration.grouping = .none  // matches `uml image --grouping none`
            return try DiagramImageRenderer.renderPNG(artifact: artifact, configuration: configuration, scale: 2)
        }
    }
}

@Suite("Sequence diagram PNG exports")
struct SequenceDiagramPNGTests {

    static let cases: [(stem: String, language: CodeArtifact.SourceLanguage)] = [
        ("swift", .swift), ("kotlin", .kotlin), ("java", .java), ("typescript", .typeScript)
    ]

    @Test("sequence PNG is valid and re-renders to the same size", arguments: cases)
    @MainActor func image(stem: String, language: CodeArtifact.SourceLanguage) throws {
        try ExamplePNGs.validate(ExamplePNGs.examples("SequenceDiagram", "Exports", "\(stem).png")) {
            let artifact = try ExamplePNGs.analyze(ExamplePNGs.examples("SequenceDiagram"), languages: [language])
            let diagram = artifact.sequenceDiagram(
                entryPoint: ("Checkout", "placeOrder"), maxDepth: 5, typeMapping: [:]
            )
            return try DiagramImageRenderer.renderPNG(sequenceDiagram: diagram, scale: 2)
        }
    }
}

@Suite("State diagram PNG exports")
struct StateDiagramPNGTests {

    static let cases: [(stem: String, language: CodeArtifact.SourceLanguage)] = [
        ("swift", .swift), ("kotlin", .kotlin), ("java", .java),
        ("typescript", .typeScript), ("javascript", .javaScript), ("dart", .dart)
    ]

    @Test("state PNG is valid and re-renders to the same size", arguments: cases)
    @MainActor func image(stem: String, language: CodeArtifact.SourceLanguage) throws {
        try ExamplePNGs.validate(ExamplePNGs.examples("StateDiagram", "Exports", "\(stem).png")) {
            let artifact = try ExamplePNGs.analyze(ExamplePNGs.examples("StateDiagram"), languages: [language])
            let configuration = StateDiagramConfiguration(typeName: "Download", variableName: "state")
            let diagram = try artifact.resolvingExtensions().stateDiagram(configuration: configuration)
            return try DiagramImageRenderer.renderPNG(stateDiagram: diagram, scale: 2)
        }
    }
}
