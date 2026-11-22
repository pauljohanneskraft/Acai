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
        specs(at: root, requestedLanguages: requestedLanguages, excluding: [], reading: nil)
    }

    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage],
        reading reads: DirectoryReadCache
    ) -> [SourceSpec] {
        specs(at: root, requestedLanguages: requestedLanguages, excluding: [], reading: reads)
    }

    private func specs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage],
        excluding claimed: Set<CodeArtifact.SourceLanguage>,
        reading reads: DirectoryReadCache?
    ) -> [SourceSpec] {
        // `SourceLanguage` is an open struct (no `.allCases`); the set of supported languages is
        // exactly the set of registered parsers, which is also more correct than a fixed enum.
        let langs: [CodeArtifact.SourceLanguage] = requestedLanguages.isEmpty
            ? parsers.map(\.language)
            : requestedLanguages
        let excludedDirectories = parsers.reduce(into: AcaiConstants.standard.defaultExcludedSourceDirectories) {
            $0.formUnion($1.configuration.excludedDirectories)
        }
        let candidates = langs
            .filter { !claimed.contains($0) }
            .compactMap { lang in parsers.first { $0.language == lang } }
        guard !candidates.isEmpty else { return [] }
        // One walk for every language rather than one each: the fallback now runs on every analysis,
        // for whichever languages no project root claimed.
        let present = FileManager.default.fileExtensionsPresent(
            in: root,
            among: Set(candidates.flatMap(\.fileExtensions).map { $0.lowercased() }),
            excludingDirectories: excludedDirectories,
            reading: reads
        )
        return candidates.compactMap { parser in
            guard parser.fileExtensions.contains(where: { present.contains($0.lowercased()) })
            else { return nil }
            return SourceSpec(language: parser.language, sourceDirs: [root], root: root)
        }
    }
}

/// A fallback that leaves the languages discovery already claimed out of its walk, so the walk can
/// stop as soon as every language still open is seen.
protocol ClaimAwareFallback {
    func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage],
        excluding claimed: Set<CodeArtifact.SourceLanguage>,
        reading reads: DirectoryReadCache
    ) -> [SourceSpec]
}

extension FallbackDetector: ClaimAwareFallback {
    func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage],
        excluding claimed: Set<CodeArtifact.SourceLanguage>,
        reading reads: DirectoryReadCache
    ) -> [SourceSpec] {
        specs(at: root, requestedLanguages: requestedLanguages, excluding: claimed, reading: reads)
    }
}
