import Foundation

public struct AcaiConstants: Sendable {
    public static let standard = AcaiConstants()

    /// Ceiling, in bytes, on a source file the analyzer will read. A larger file is skipped and
    /// recorded as a `.skipped` ``ParseDiagnostic`` carrying its size, so it shows up in the health
    /// report rather than silently costing memory and parse time.
    ///
    /// The default is generous — an ordinary hand-written source file is orders of magnitude
    /// smaller — and exists to bound the pathological case: a bundled `.js`, a vendored single-file
    /// library or a generated file that escaped every exclusion, read whole into a `String`.
    public let maximumSourceFileBytes: Int

    public init(maximumSourceFileBytes: Int = 2 * 1024 * 1024) {
        self.maximumSourceFileBytes = maximumSourceFileBytes
    }

    private var baseDirectory: URL {
        #if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".acai")
        #else
        (try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory.appendingPathComponent("acai", isDirectory: true)
        #endif
    }

    public var analysisDirectory: URL {
        baseDirectory.appendingPathComponent("analysis")
    }

    /// Directories skipped while collecting sources regardless of language. Only the universal
    /// version-control directory lives here; each language's build-output/dependency directories
    /// (`node_modules`, `Pods`, `target`, …) come from its `LanguageConfiguration.excludedDirectories`
    /// and are unioned in by the composition root.
    public let defaultExcludedSourceDirectories: Set<String> = [".git"]

    /// Directory names that hold stand-in or third-party projects rather than the codebase under
    /// analysis, so a manifest inside one is not a project root. Matched on the name alone, without
    /// regard to case. These are generic repository conventions, not any one language's: a manifest
    /// under `Fixtures/` is a fixture whichever build system wrote it.
    ///
    /// This governs root *discovery* only. Such a directory is still collected when a root above it
    /// claims it as a source directory, and analysing one directly still works — what it cannot do is
    /// become a root of its own while a real project is being walked.
    public let defaultNonRootDirectories: Set<String> = [
        "fixtures", "testdata", "test-data", "testfixtures",
        "third_party", "thirdparty", "vendor", "vendored"
    ]

    /// Schema/tool version stamped into every analyzed `CodeArtifact`'s metadata. Bump when the
    /// stored `CodeArtifact` JSON shape changes in a way consumers need to detect.
    public let toolVersion = "1.0.0"
}
