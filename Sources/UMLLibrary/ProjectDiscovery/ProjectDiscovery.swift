import Foundation
import UMLCore

// MARK: - Project Discovery Coordinator

/// Coordinates build-system detectors to discover which languages and source directories
/// to analyse in a project root.
///
/// Detectors are tried in priority order. The first detector that claims a language wins;
/// later detectors returning the same language are ignored (e.g. SPM takes priority over
/// Xcode for Swift). The `fallback` detector activates only when no registered detector matched.
public struct ProjectDiscovery: Sendable {

    /// Ordered list of build-system detectors, tried in sequence.
    public let detectors: [any BuildSystemDetector]

    /// Used when no detector in `detectors` matches.
    public let fallback: any BuildSystemDetector

    public init(detectors: [any BuildSystemDetector], fallback: any BuildSystemDetector) {
        self.detectors = detectors
        self.fallback = fallback
    }

    /// Returns one `SourceSpec` per discovered language, deduplicated by language
    /// so that the first matching detector per language wins.
    public func discoverSourceSpecs(
        in rootURL: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        var specs: [SourceSpec] = []
        var seenLanguages: Set<CodeArtifact.SourceLanguage> = []

        for detector in detectors where detector.isPresent(at: rootURL) {
            for spec in detector.discoverSourceSpecs(at: rootURL, requestedLanguages: requestedLanguages)
                where seenLanguages.insert(spec.language).inserted {
                specs.append(spec)
            }
        }

        if specs.isEmpty {
            specs = fallback.discoverSourceSpecs(at: rootURL, requestedLanguages: requestedLanguages)
        }

        return specs
    }
}
