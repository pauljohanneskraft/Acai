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
        let candidates = langs.compactMap { lang in parsers.first { $0.language == lang } }
        // One walk for every language rather than one each: the fallback now runs on every analysis,
        // for whichever languages no project root claimed.
        let present = FileManager.default.fileExtensionsPresent(
            in: root,
            among: Set(candidates.flatMap(\.fileExtensions).map { $0.lowercased() }),
            excludingDirectories: excludedDirectories
        )
        return candidates.compactMap { parser in
            guard parser.fileExtensions.contains(where: { present.contains($0.lowercased()) })
            else { return nil }
            return SourceSpec(language: parser.language, sourceDirs: [root], root: root)
        }
    }
}
