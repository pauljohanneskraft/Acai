import UMLCore
import UMLSwift
import UMLJS
import UMLJVM
import UMLDart
import UMLPython
import UMLCFamily

// The one place that names the built-in languages. Assembling the standard parser set and the
// concrete build-system detectors here keeps `AnalysisService` (and the rest of the engine)
// language-agnostic — adding or swapping a language is a change to this composition root only.
extension AnalysisService {

    /// The standard parser set covering every built-in language.
    public static let standardParsers: [any CodeParser] = [
        SwiftCodeParser(),
        KotlinCodeParser(),
        JavaCodeParser(),
        JSCodeParser(isTypeScript: true),
        JSCodeParser(isTypeScript: false),
        DartCodeParser(),
        PythonCodeParser(),
        CCodeParser(),
        CppCodeParser()
    ]

    /// The standard build-system detectors. Each concrete detector now lives in its language
    /// target; this list merely orders them (priority order — SPM before Xcode for Swift, etc.).
    public static var standardDetectors: [any BuildSystemDetector] {
        [
            SwiftPackageManagerDetector(),
            XcodeDetector(),
            JVMBuildSystemDetector.gradle,
            JVMBuildSystemDetector.maven,
            NodeDetector(),
            FlutterDetector(),
            PythonDetector(),
            CFamilyBuildSystemDetector.cmake,
            CFamilyBuildSystemDetector.make,
            CFamilyBuildSystemDetector.meson
        ]
    }

    /// Batteries-included service: all built-in parsers with auto-detected project layout.
    public static let standard = AnalysisService(
        parsers: standardParsers,
        projectDiscovery: ProjectDiscovery(
            detectors: standardDetectors,
            fallback: FallbackDetector(parsers: standardParsers)
        )
    )
}

extension CodeArtifact {
    /// The single place the app/CLI/MCP turn an artifact into its per-type language quirks before handing
    /// them to the agnostic engine: a `LanguageConfigurationResolver` over the standard registry that
    /// classifies **each type** by its own stamped `sourceLanguage`. A mixed Swift+Python codebase is
    /// therefore styled, enriched and filtered with each language's own rules rather than one dominant
    /// config, while a single-language codebase is byte-for-byte unchanged.
    ///
    /// Its default (used for a type with no stamped language, or a language not in the standard set —
    /// neither of which happens for artifacts produced by `AnalysisService.standard`) is the artifact's
    /// top-level language config, keeping the UI/CLI robust to a hand-loaded artifact rather than crashing.
    /// There is deliberately no public single-config accessor: resolving one flat config per artifact was
    /// the polyglot bug this replaced.
    public var standardLanguageResolver: LanguageConfigurationResolver {
        let registry = AnalysisService.standard.registry
        let fallback = registry.configuration(for: metadata.sourceLanguage) ?? LanguageConfiguration()
        return LanguageConfigurationResolver(registry: registry, default: fallback)
    }
}
