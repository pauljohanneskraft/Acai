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
    /// This artifact's `LanguageConfiguration` resolved from the standard registry — the single
    /// place the app/CLI turn a `sourceLanguage` into its quirks before handing them to the
    /// agnostic diagram layer.
    ///
    /// Returns an empty configuration only for a language not in the standard set, which cannot
    /// happen for artifacts produced by `AnalysisService.standard`; it keeps the UI/CLI robust to a
    /// hand-loaded artifact with an unknown language rather than crashing.
    public var standardLanguageConfiguration: LanguageConfiguration {
        AnalysisService.standard.registry.configuration(for: metadata.sourceLanguage)
            ?? LanguageConfiguration()
    }
}
