import Foundation
import UMLCore

/// Detects C / C++ projects by their shared build systems (CMake, Make, Meson) and reports a
/// `SourceSpec` for each C-family language whose sources are present.
///
/// One detector serves both languages — like `JVMBuildSystemDetector` serves Java and Kotlin —
/// because the build systems are shared and a single project routinely mixes `.c` and `.cpp`. Which
/// parser handles an ambiguous `.h` header is decided per file by `CCodeParser`, not here.
public struct CFamilyBuildSystemDetector: BuildSystemDetector {

    /// File names (relative to the project root) whose presence signals this build system.
    public let indicatorFiles: [String]

    public init(indicatorFiles: [String]) {
        self.indicatorFiles = indicatorFiles
    }

    /// Preset for CMake projects.
    public static let cmake = CFamilyBuildSystemDetector(indicatorFiles: ["CMakeLists.txt"])

    /// Preset for Make projects.
    public static let make = CFamilyBuildSystemDetector(
        indicatorFiles: ["Makefile", "makefile", "GNUmakefile"])

    /// Preset for Meson projects.
    public static let meson = CFamilyBuildSystemDetector(indicatorFiles: ["meson.build"])

    private static let cExtensions: Set<String> = ["c"]
    private static let cppExtensions: Set<String> = [
        "cpp", "cc", "cxx", "c++", "hpp", "hh", "hxx", "h++", "ipp", "tpp"
    ]

    public func isPresent(at root: URL) -> Bool {
        indicatorFiles.contains {
            FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
        }
    }

    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        func wants(_ language: CodeArtifact.SourceLanguage) -> Bool {
            requestedLanguages.isEmpty || requestedLanguages.contains(language)
        }

        var specs: [SourceSpec] = []
        // `.c` files signal C; any C++-only extension signals C++. A project with only `.h` headers
        // is reported as C — `CCodeParser` still routes individual C++ headers to the C++ grammar.
        if wants(.c), hasFiles(Self.cExtensions.union(["h"]), at: root) {
            specs.append(SourceSpec(language: .c, sourceDirs: [root]))
        }
        if wants(.cpp), hasFiles(Self.cppExtensions, at: root) {
            specs.append(SourceSpec(language: .cpp, sourceDirs: [root]))
        }
        return specs
    }

    private func hasFiles(_ extensions: Set<String>, at root: URL) -> Bool {
        !FileManager.default.fileURLs(
            in: root, withExtensions: extensions,
            excludingDirectories: CFamilyDialect.excludedDirectories
        ).isEmpty
    }
}
