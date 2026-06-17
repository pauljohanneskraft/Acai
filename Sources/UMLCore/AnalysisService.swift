import Foundation

// MARK: - Analysis Service

/// Orchestrates parsing: maps languages to their `CodeParser`, runs files through them,
/// and merges results into a single `CodeArtifact`.
///
/// Language-agnostic by construction: it holds whatever parsers and project-discovery strategy it
/// is given and knows nothing about any specific language. The standard, batteries-included set of
/// languages is assembled in the composition root (`UMLLibrary`) as `AnalysisService.standard`.
public struct AnalysisService: Sendable {

    // MARK: - Properties

    /// The parsers this service uses, one per supported language.
    public let parsers: [any CodeParser]

    /// The project-discovery coordinator used by `analyzeProject`.
    public let projectDiscovery: ProjectDiscovery

    /// Per-language quirks for the parsers in this service, for downstream stages to look up by
    /// `CodeArtifact.metadata.sourceLanguage`.
    public var registry: LanguageRegistry { LanguageRegistry(parsers: parsers) }

    // MARK: - Initialisation

    /// Creates a service from an explicit parser set and discovery strategy. When `projectDiscovery`
    /// is omitted, only the parser-driven `FallbackDetector` is used (no build-system detection); the
    /// composition root supplies the concrete detectors.
    public init(
        parsers: [any CodeParser],
        projectDiscovery: ProjectDiscovery? = nil
    ) {
        self.parsers = parsers
        self.projectDiscovery = projectDiscovery ?? ProjectDiscovery(
            detectors: [],
            fallback: FallbackDetector(parsers: parsers)
        )
    }

    // MARK: - Parser Registry

    /// Returns the parser registered for `language`, or `nil` when none is registered.
    ///
    /// Returning `nil` rather than silently substituting a parser surfaces the bug of a language
    /// reaching analysis without being wired into ``parsers`` (a trap when adding a language)
    /// instead of masking it as mis-parsed by the wrong language.
    public func parser(for language: CodeArtifact.SourceLanguage) -> (any CodeParser)? {
        parsers.first { $0.language == language }
    }

    // MARK: - Project Analysis

    /// Auto-discovers source directories via `projectDiscovery`, then parses and merges all files.
    public func analyzeProject(
        at rootURL: URL,
        allowedLanguages: [CodeArtifact.SourceLanguage]
    ) throws -> CodeArtifact {
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            throw ValidationError("Source directory does not exist: \(rootURL.path)")
        }

        let specs = projectDiscovery.discoverSourceSpecs(in: rootURL, requestedLanguages: allowedLanguages)

        guard !specs.isEmpty else {
            let hint = allowedLanguages.isEmpty
                ? "Use --language to specify a language explicitly."
                : "No \(allowedLanguages.map(\.rawValue).joined(separator: "/")) source files found."
            throw ValidationError("Could not discover any source files in \(rootURL.path). \(hint)")
        }

        var combinedArtifact: CodeArtifact?

        for spec in specs {
            if let artifact = parseSpec(spec, rootURL: rootURL) {
                combinedArtifact = combinedArtifact.map { $0.merging(with: artifact) } ?? artifact
            }
        }

        guard let result = combinedArtifact else {
            throw ValidationError("No source files could be parsed in \(rootURL.path).")
        }
        return result
    }

    /// Parses all files for a single language spec and returns the combined artifact.
    private func parseSpec(
        _ spec: SourceSpec,
        rootURL: URL
    ) -> CodeArtifact? {
        guard let codeParser = parser(for: spec.language) else {
            assertionFailure(
                "No parser registered for language \(spec.language); wire it into AnalysisService.parsers."
            )
            print("Warning: No parser registered for language \(spec.language.rawValue); skipping it.")
            return nil
        }
        let exts = Set(codeParser.fileExtensions)
        // Skip every registered language's build-output/dependency directories (plus the universal
        // VCS dir) so e.g. a JS project's `node_modules` is never walked.
        let excludedDirectories = registry.excludedDirectories
            .union(UMLConstants.defaultExcludedSourceDirectories)

        let files = spec.sourceDirs
            .flatMap {
                FileManager.default.fileURLs(
                    in: $0, withExtensions: exts, excludingDirectories: excludedDirectories
                )
            }
            .removingDuplicates { $0 }

        guard !files.isEmpty else { return nil }

        var artifact = CodeArtifact(
            metadata: .init(sourceLanguage: spec.language, filePaths: [], toolVersion: "1.0.0")
        )

        for file in files {
            let relativePath = file.relativePath(from: rootURL)
            do {
                let source = try String(contentsOf: file, encoding: .utf8)
                let parsed = codeParser.parse(source: source, fileName: relativePath)
                artifact = artifact.merging(with: parsed)
            } catch {
                print("Warning: Failed to parse \(relativePath): \(error.localizedDescription)")
            }
        }

        // Run the generalizable enrichment pipeline (extension resolution, name→id
        // resolution, inheritance/conformance reclassification, inferred structural
        // edges, dedup) so the emitted artifact is fully resolved for every language.
        // The parser's configuration supplies the language's type-name classification.
        return artifact.enriched(configuration: codeParser.configuration)
    }
}

extension URL {
    /// Returns a path relative to `base`, or the last path component if unrelated.
    func relativePath(from base: URL) -> String {
        if path.hasPrefix(base.path) {
            return String(path.dropFirst(base.path.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return lastPathComponent
    }}
