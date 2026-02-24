import Foundation
import UMLCore

/// Last-resort detector used when no recognised build system is found.
///
/// Scans the project root for all known source file extensions and returns
/// a `SourceSpec` for each language that has at least one matching file.
public struct FallbackDetector: BuildSystemDetector {

    /// The parsers used to resolve file extensions for each language.
    public let parsers: [any CodeParser]

    public init(parsers: [any CodeParser]) {
        self.parsers = parsers
    }

    public func isPresent(at root: URL) -> Bool { true }

    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        let langs: [CodeArtifact.SourceLanguage] = requestedLanguages.isEmpty
            ? CodeArtifact.SourceLanguage.allCases
            : requestedLanguages
        return langs.compactMap { lang in
            guard let parser = parsers.first(where: { $0.language == lang }) else { return nil }
            let exts = Set(parser.fileExtensions)
            guard !FileManager.default.fileURLs(in: root, withExtensions: exts).isEmpty else { return nil }
            return SourceSpec(language: lang, sourceDirs: [root])
        }
    }
}
