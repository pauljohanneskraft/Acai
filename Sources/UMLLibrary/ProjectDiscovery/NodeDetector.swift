import Foundation
import UMLCore

/// Detects Node.js projects (`package.json`) and locates TypeScript / JavaScript sources.
///
/// Reads `tsconfig.json` (when present) to find configured source directories;
/// falls back to a `src/` subdirectory or the project root.
public struct NodeDetector: BuildSystemDetector {
    public func isPresent(at root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent("package.json").path)
    }

    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        func wants(_ lang: CodeArtifact.SourceLanguage) -> Bool {
            requestedLanguages.isEmpty || requestedLanguages.contains(lang)
        }

        let searchDirs = tsConfigSourceDirs(in: root) ?? defaultSourceDirs(in: root)

        let hasTS = searchDirs.contains(where: {
            !FileManager.default.fileURLs(in: $0, withExtensions: ["ts", "tsx"]).isEmpty
        })
        let hasJS = searchDirs.contains(where: {
            !FileManager.default.fileURLs(in: $0, withExtensions: ["js", "jsx", "mjs"]).isEmpty
        })

        var specs: [SourceSpec] = []

        if hasTS, wants(.typeScript) {
            specs.append(SourceSpec(language: .typeScript, sourceDirs: searchDirs))
        }
        // Add JavaScript only when JS files exist AND the project isn't purely TypeScript,
        // or the user explicitly requested JavaScript.
        let userExplicitlyWantsJS = requestedLanguages.contains(.javaScript)
        if hasJS, wants(.javaScript), !hasTS || userExplicitlyWantsJS {
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

    private func defaultSourceDirs(in rootURL: URL) -> [URL] {
        let srcDir = rootURL.appendingPathComponent("src")
        return FileManager.default.fileExists(atPath: srcDir.path) ? [srcDir] : [rootURL]
    }
}
