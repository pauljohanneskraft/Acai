import Foundation
import AcaiCore

/// Detects C / C++ projects by their shared build systems (CMake, Make, Meson) and reports a
/// `SourceSpec` for each C-family language whose sources are present.
///
/// One detector serves both languages — like `JVMBuildSystemDetector` serves Java and Kotlin —
/// because the build systems are shared and a single project routinely mixes `.c` and `.cpp`. Which
/// parser handles an ambiguous `.h` header is decided per file by `CCodeParser`, not here.
public struct CFamilyBuildSystemDetector: BuildSystemDetector {

    public let indicatorFiles: [String]

    /// The listfiles whose `add_subdirectory()` calls declare nested project roots.
    public let subdirectoryFiles: [String]

    public init(indicatorFiles: [String], subdirectoryFiles: [String] = []) {
        self.indicatorFiles = indicatorFiles
        self.subdirectoryFiles = subdirectoryFiles
    }

    public static let cmake = CFamilyBuildSystemDetector(
        indicatorFiles: ["CMakeLists.txt"], subdirectoryFiles: ["CMakeLists.txt"])

    public static let make = CFamilyBuildSystemDetector(
        indicatorFiles: ["Makefile", "makefile", "GNUmakefile"])

    public static let meson = CFamilyBuildSystemDetector(indicatorFiles: ["meson.build"])

    public func isPresent(at root: URL) -> Bool {
        IndicatorFiles(indicatorFiles).present(at: root)
    }

    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        let request = LanguageRequest(requestedLanguages)
        let nested = nestedRoots(at: root)
        var specs: [SourceSpec] = []
        // `.c` files signal C; any C++-only extension signals C++. A project with only `.h` headers
        // is reported as C — `CCodeParser` still routes individual C++ headers to the C++ grammar.
        if request.wants(.c), cFiles.exist(in: root) {
            specs.append(spec(.c, at: root, nested: nested))
        }
        if request.wants(.cpp), cppFiles.exist(in: root) {
            specs.append(spec(.cpp, at: root, nested: nested))
        }
        return specs
    }

    private func spec(
        _ language: CodeArtifact.SourceLanguage, at root: URL, nested: NestedRoots
    ) -> SourceSpec {
        SourceSpec(
            language: language,
            sourceDirs: [root],
            root: root,
            nestedRootPaths: nested.directories,
            diagnostics: nested.diagnostics)
    }

    /// A declared directory without a listfile of its own is no root, so it stays part of this one.
    private func nestedRoots(at root: URL) -> NestedRoots {
        var nested = NestedRoots()
        for file in subdirectoryFiles {
            let listfile = root.appending(path: file)
            do {
                let declarations = CMakeListsFile(
                    source: try String(contentsOf: listfile, encoding: .utf8)).subdirectories
                collect(declarations, declaredIn: file, at: root, into: &nested)
            } catch {
                guard FileManager.default.fileExists(atPath: listfile.path) else { continue }
                nested.diagnostics.append(unreadableListfileDiagnostic(file, error: error))
            }
        }
        nested.directories = nested.directories.removingDuplicates { $0.path }
        return nested
    }

    private func collect(
        _ declarations: [CMakeListsFile.Declaration], declaredIn file: String, at root: URL,
        into nested: inout NestedRoots
    ) {
        let indicator = IndicatorFiles(indicatorFiles)
        let rootPath = root.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        for declaration in declarations {
            switch declaration.directory {
            case .literal(let path):
                let directory = (path.hasPrefix("/") ? URL(filePath: path) : root.appending(path: path))
                    .standardizedFileURL
                guard directory.path.hasPrefix(rootPrefix), indicator.present(at: directory) else { continue }
                nested.directories.append(directory)
            case .computed(let argument):
                nested.diagnostics.append(
                    computedDirectoryDiagnostic(argument, in: file, line: declaration.line))
            }
        }
    }

    private func unreadableListfileDiagnostic(_ file: String, error: any Error) -> ParseDiagnostic {
        ParseDiagnostic(
            location: SourceLocation(filePath: file, line: 1, column: 1),
            kind: .incompleteDiscovery,
            message: "\(file) could not be read (\(error.localizedDescription)), so any nested "
                + "project root it declares was not reported."
        )
    }

    private func computedDirectoryDiagnostic(_ argument: String, in file: String, line: Int) -> ParseDiagnostic {
        ParseDiagnostic(
            location: SourceLocation(filePath: file, line: line, column: 1),
            kind: .incompleteDiscovery,
            message: "add_subdirectory(\(argument)) in \(file) names a directory CMake expands at "
                + "configure time, so it was not discovered as a project root of its own. Any sources "
                + "it holds are analysed as part of the root declaring it instead."
        )
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

private struct NestedRoots {
    var directories: [URL] = []
    var diagnostics: [ParseDiagnostic] = []
}
