import Foundation
import AcaiCore

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

    public func isPresent(at root: URL) -> Bool {
        IndicatorFiles(indicatorFiles).present(at: root)
    }

    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        let request = LanguageRequest(requestedLanguages)
        var specs: [SourceSpec] = []
        // `.c` files signal C; any C++-only extension signals C++. A project with only `.h` headers
        // is reported as C — `CCodeParser` still routes individual C++ headers to the C++ grammar.
        if request.wants(.c), cFiles.exist(in: root) {
            specs.append(SourceSpec(language: .c, sourceDirs: [root]))
        }
        if request.wants(.cpp), cppFiles.exist(in: root) {
            specs.append(SourceSpec(language: .cpp, sourceDirs: [root]))
        }
        return specs
    }

    // C-family exclusion is a shared dialect setting, so these presences are declared once as locals.
    private var cFiles: SourceFilePresence {
        SourceFilePresence(extensions: ["c", "h"], excludingDirectories: CFamilyDialect.excludedDirectories)
    }
    private var cppFiles: SourceFilePresence {
        SourceFilePresence(
            extensions: ["cpp", "cc", "cxx", "c++", "hpp", "hh", "hxx", "h++", "ipp", "tpp"],
            excludingDirectories: CFamilyDialect.excludedDirectories)
    }
}
