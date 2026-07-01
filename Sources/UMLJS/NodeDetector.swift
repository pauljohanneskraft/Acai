import Foundation
import UMLCore

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
        let request = LanguageRequest(requestedLanguages)
        let searchDirs = tsConfigSourceDirs(in: root)
            ?? SourceDirectoryProbe(preferring: "src").directories(in: root)

        let hasTS = SourceFilePresence(extensions: ["ts", "tsx"]).exist(inAnyOf: searchDirs)
        let hasJS = SourceFilePresence(extensions: ["js", "jsx", "mjs"]).exist(inAnyOf: searchDirs)

        var specs: [SourceSpec] = []

        if hasTS, request.wants(.typeScript) {
            specs.append(SourceSpec(language: .typeScript, sourceDirs: searchDirs))
        }
        // Add JavaScript only when JS files exist AND the project isn't purely TypeScript,
        // or the user explicitly requested JavaScript.
        if hasJS, request.wants(.javaScript), !hasTS || request.explicitlyWants(.javaScript) {
            specs.append(SourceSpec(language: .javaScript, sourceDirs: searchDirs))
        }

        return specs
    }

    // MARK: - tsconfig.json Parsing

    /// Reads `tsconfig.json` and returns configured source directories.
    /// Returns `nil` if the file is absent or provides no path information.
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
