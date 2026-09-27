import Foundation
import AcaiCore
import AcaiLibrary

/// The feature matrix's on-disk corpus: one directory per canonical language feature, holding one
/// idiomatic snippet per language (or a `.waiver` saying why the language cannot express it) beside
/// the single hand-written `<feature>.expected.json` every language has to normalise to.
///
/// Read by `#filePath`, like `ParserGoldenCorpus` — the snippets are `excluded` in `Package.swift` so
/// SwiftPM leaves the `.swift`/`.c`/`.cpp` ones as parser input instead of compiling them into this
/// target.
struct ContractFeatureCorpus {

    /// One language's place in the matrix: the file stem its snippets use, the extension it parses
    /// under, and the parser plus configuration the engine really uses for it.
    struct Language: Sendable, CustomStringConvertible {
        let stem: String
        let fileExtension: String
        let parser: any CodeParser

        var description: String { stem }

        var configuration: LanguageConfiguration {
            AnalysisService.standard.registry.configuration(for: parser.language) ?? parser.configuration
        }
    }

    enum Failure: Error, CustomStringConvertible {
        case missingSnippet(feature: String, language: String, expectedPath: String, waiverPath: String)
        case emptyWaiver(feature: String, language: String, path: String)
        case missingExpectation(feature: String, path: String)

        var description: String {
            switch self {
            case .missingSnippet(let feature, let language, let expectedPath, let waiverPath):
                return "'\(feature)' has no \(language) snippet. Add \(expectedPath), or — only if the "
                    + "language genuinely cannot express the feature — \(waiverPath) with a one-line reason."
            case .emptyWaiver(let feature, let language, let path):
                return "\(path) waives '\(feature)' for \(language) without a reason; state why the "
                    + "language cannot express the feature."
            case .missingExpectation(let feature, let path):
                return "'\(feature)' has no expected shape at \(path)."
            }
        }
    }

    let directory: URL

    init(testFile: StaticString = #filePath) {
        directory = URL(fileURLWithPath: "\(testFile)")
            .deletingLastPathComponent()
            .appendingPathComponent("Features")
    }

    /// Every language `AnalysisService.standard` parses. JavaScript is listed separately from
    /// TypeScript: it is a different parser with no type annotations, so it earns its own row (and its
    /// own waivers) rather than hiding behind TypeScript's.
    let languages: [Language] = [
        Language(stem: "swift", fileExtension: "swift", parser: SwiftCodeParser()),
        Language(stem: "kotlin", fileExtension: "kt", parser: KotlinCodeParser()),
        Language(stem: "java", fileExtension: "java", parser: JavaCodeParser()),
        Language(stem: "typescript", fileExtension: "ts", parser: JSCodeParser(isTypeScript: true)),
        Language(stem: "javascript", fileExtension: "js", parser: JSCodeParser(isTypeScript: false)),
        Language(stem: "dart", fileExtension: "dart", parser: DartCodeParser()),
        Language(stem: "python", fileExtension: "py", parser: PythonCodeParser()),
        Language(stem: "c", fileExtension: "c", parser: CCodeParser()),
        Language(stem: "cpp", fileExtension: "cpp", parser: CppCodeParser())
    ]

    /// Derived from the directory listing, so adding a feature folder is all it takes to hold every
    /// language to it.
    var features: [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .sorted()
    }

    func snippetURL(feature: String, language: Language) -> URL {
        directory
            .appendingPathComponent(feature)
            .appendingPathComponent("\(language.stem).\(language.fileExtension)")
    }

    func waiverURL(feature: String, language: Language) -> URL {
        directory.appendingPathComponent(feature).appendingPathComponent("\(language.stem).waiver")
    }

    func expectationURL(feature: String) -> URL {
        directory.appendingPathComponent("\(feature).expected.json")
    }

    /// The reason this language is excused from the feature, or `nil` when it must provide a snippet.
    func waiver(feature: String, language: Language) throws -> String? {
        let url = waiverURL(feature: feature, language: language)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let reason = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else {
            throw Failure.emptyWaiver(feature: feature, language: language.stem, path: relativePath(of: url))
        }
        return reason
    }

    func snippet(feature: String, language: Language) throws -> (source: String, fileName: String) {
        let url = snippetURL(feature: feature, language: language)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Failure.missingSnippet(
                feature: feature, language: language.stem,
                expectedPath: relativePath(of: url),
                waiverPath: relativePath(of: waiverURL(feature: feature, language: language)))
        }
        return (try String(contentsOf: url, encoding: .utf8), url.lastPathComponent)
    }

    func expectation(feature: String) throws -> ContractShape {
        let url = expectationURL(feature: feature)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Failure.missingExpectation(feature: feature, path: relativePath(of: url))
        }
        return try JSONDecoder().decode(ContractShape.self, from: Data(contentsOf: url))
    }

    /// The shape `language` produces for `feature`, through the same parse → enrich path the engine
    /// runs, then the normaliser.
    func shape(feature: String, language: Language) throws -> ContractShape {
        let snippet = try self.snippet(feature: feature, language: language)
        let parsed = language.parser.parse(source: snippet.source, fileName: snippet.fileName)
        let enriched = parsed.enriched(configuration: language.configuration)
        return ContractNormalizer(configuration: language.configuration).shape(of: enriched)
    }

    private func relativePath(of url: URL) -> String {
        let components = url.pathComponents
        guard let root = components.lastIndex(of: "Tests") else { return url.path }
        return components[root...].joined(separator: "/")
    }
}
