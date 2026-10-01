import Foundation
import AcaiCore

/// Detects Node.js projects (`package.json`) and locates TypeScript / JavaScript sources.
///
/// Reads `tsconfig.json` (when present) to find configured source directories;
/// falls back to a `src/` subdirectory or the project root.
public struct NodeDetector: BuildSystemDetector {
    public init() {}

    public func isPresent(at root: URL) -> Bool {
        IndicatorFiles(["package.json"]).present(at: root)
    }

    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        Layout(root: root, searchDirs: searchDirs(in: root))
            .specs(for: LanguageRequest(requestedLanguages))
    }

    /// A TypeScript project's JavaScript is config and build output, not source.
    public func withheldLanguages(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> Set<CodeArtifact.SourceLanguage> {
        Layout(root: root, searchDirs: searchDirs(in: root))
            .withheldLanguages(for: LanguageRequest(requestedLanguages))
    }

    /// Resolves the layout once and answers both halves from it. Asked separately, each would
    /// re-read `tsconfig.json` and walk the sources again — per `package.json`, so once per workspace
    /// in a monorepo now that detectors run at every directory.
    public func claim(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> DetectorClaim {
        let layout = Layout(root: root, searchDirs: searchDirs(in: root))
        let request = LanguageRequest(requestedLanguages)
        return DetectorClaim(
            specs: layout.specs(for: request),
            withheldLanguages: layout.withheldLanguages(for: request)
        )
    }

    private func searchDirs(in root: URL) -> [URL] {
        tsConfigSourceDirs(in: root) ?? SourceDirectoryProbe(preferring: "src").directories(in: root)
    }

    // MARK: - Resolved Layout

    /// One Node root's resolved layout: which directories hold its sources, and which languages those
    /// directories actually contain.
    private struct Layout {
        let root: URL
        let searchDirs: [URL]
        /// Decides both halves of the claim, so it is resolved eagerly. JavaScript presence is not:
        /// only `specs(for:)` needs it, and only once TypeScript has not already ruled it out.
        let hasTypeScript: Bool

        init(root: URL, searchDirs: [URL]) {
            self.root = root
            self.searchDirs = searchDirs
            self.hasTypeScript = SourceFilePresence(extensions: ["ts", "tsx"]).exist(inAnyOf: searchDirs)
        }

        func specs(for request: LanguageRequest) -> [SourceSpec] {
            var specs: [SourceSpec] = []
            if hasTypeScript, request.wants(.typeScript) {
                specs.append(SourceSpec(language: .typeScript, sourceDirs: searchDirs, root: root))
            }
            if request.wants(.javaScript), !hasTypeScript || request.explicitlyWants(.javaScript),
               SourceFilePresence(extensions: ["js", "jsx", "mjs"]).exist(inAnyOf: searchDirs) {
                specs.append(SourceSpec(language: .javaScript, sourceDirs: searchDirs, root: root))
            }
            return specs
        }

        func withheldLanguages(for request: LanguageRequest) -> Set<CodeArtifact.SourceLanguage> {
            guard request.wants(.javaScript), !request.explicitlyWants(.javaScript), hasTypeScript
            else { return [] }
            return [.javaScript]
        }
    }

    // MARK: - tsconfig.json Parsing

    private func tsConfigSourceDirs(in rootURL: URL) -> [URL]? {
        let tsconfigURL = rootURL.appendingPathComponent("tsconfig.json")
        guard
            let data = try? Data(contentsOf: tsconfigURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var dirs: [URL] = []
        var seen: Set<URL> = []

        func addIfNew(_ url: URL) {
            let std = url.standardizedFileURL
            if seen.insert(std).inserted { dirs.append(std) }
        }

        if let compilerOpts = json["compilerOptions"] as? [String: Any],
           let rootDir = compilerOpts["rootDir"] as? String {
            addIfNew(rootURL.appendingPathComponent(rootDir))
        }

        if let includes = json["include"] as? [String] {
            for pattern in includes {
                let dirParts = pattern.components(separatedBy: "/")
                    .prefix(while: { !$0.contains("*") && !$0.contains("?") && !$0.isEmpty })
                if !dirParts.isEmpty {
                    addIfNew(rootURL.appendingPathComponent(dirParts.joined(separator: "/")))
                }
            }
        }

        return dirs.isEmpty ? nil : dirs
    }
}
