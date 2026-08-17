import Foundation

public struct FallbackDetector: BuildSystemDetector {
    public let parsers: [any CodeParser]

    public init(parsers: [any CodeParser]) {
        self.parsers = parsers
    }

    public func isPresent(at root: URL) -> Bool { true }

    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        // `SourceLanguage` is an open struct (no `.allCases`); the set of supported languages is
        // exactly the set of registered parsers, which is also more correct than a fixed enum.
        let langs: [CodeArtifact.SourceLanguage] = requestedLanguages.isEmpty
            ? parsers.map(\.language)
            : requestedLanguages
        let excludedDirectories = parsers.reduce(into: AcaiConstants.standard.defaultExcludedSourceDirectories) {
            $0.formUnion($1.configuration.excludedDirectories)
        }
        return langs.compactMap { lang in
            guard let parser = parsers.first(where: { $0.language == lang }) else { return nil }
            let exts = Set(parser.fileExtensions)
            guard !FileManager.default.fileURLs(
                in: root, withExtensions: exts, excludingDirectories: excludedDirectories
            ).isEmpty else { return nil }
            return SourceSpec(language: lang, sourceDirs: [root])
        }
    }
}
