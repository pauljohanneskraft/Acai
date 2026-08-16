import AcaiCore
import AcaiSwift
import AcaiJS
import AcaiJVM
import AcaiDart
import AcaiPython
import AcaiCFamily

// The one place that names the built-in languages. Assembling the standard parser set and the
// concrete build-system detectors here keeps `AnalysisService` (and the rest of the engine)
// language-agnostic — adding or swapping a language is a change to this composition root only.
extension AnalysisService {

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

    /// Order matters: `ProjectDiscovery` gives the first detector per language priority
    /// (e.g. SPM before Xcode for Swift).
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

    public static let standard = AnalysisService(
        parsers: standardParsers,
        projectDiscovery: ProjectDiscovery(
            detectors: standardDetectors,
            fallback: FallbackDetector(parsers: standardParsers)
        )
    )
}

extension CodeArtifact {
    /// Classifies **each type** by its own stamped `sourceLanguage`, so a mixed-language codebase is
    /// styled/enriched/filtered per-language rather than by one dominant config. Falls back to the
    /// artifact's top-level config for an unstamped or unregistered language.
    public var standardLanguageResolver: LanguageConfigurationResolver {
        let registry = AnalysisService.standard.registry
        let fallback = registry.configuration(for: metadata.sourceLanguage) ?? LanguageConfiguration()
        return LanguageConfigurationResolver(registry: registry, default: fallback)
    }
}
