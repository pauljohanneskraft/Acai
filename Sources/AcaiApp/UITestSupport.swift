import Foundation

/// Resolves a UI-test fixture's base directory from a launch argument, so `ProjectStore` can be
/// pointed at deterministic, disposable state instead of the real user's Application
/// Support/Documents directory. Fully inert (`resolveBaseDir()` returns `nil`) unless
/// `-AcaiUITestFixtureBaseDir <path>` is actually present in `ProcessInfo.arguments` — a real
/// user's launch never carries it, so this changes no behavior outside `App/AcaiUITests`.
///
/// The path itself is resolved and staged **by the test process**, not this one: `App/AcaiUITests`
/// (a separate Xcode-project target, not this SwiftPM package — no shared internal API) copies its
/// bundled `Fixtures/<name>` resource to a fresh temporary directory before launch and passes that
/// directory's absolute path here — see `XCUIApplication.launchWithFixture(_:)` in
/// `App/AcaiUITests/Support/Launch.swift`. Keeping fixture data entirely test-side, rather than
/// bundling it into the shipped app target, means no test-only data ever ships to a real user.
/// **The launch-argument name below and the one in `Launch.swift` must match** — they can't share
/// a constant across the SwiftPM package / Xcode-project boundary. See `TESTING_ARCHITECTURE.md`
/// Layer 2.
struct UITestFixtureResolver {
    static let launchArgument = "-AcaiUITestFixtureBaseDir"

    private let arguments: [String]

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.arguments = arguments
    }

    /// The staged fixture directory passed via `-AcaiUITestFixtureBaseDir <path>`, if any.
    func resolveBaseDir() -> URL? {
        guard let flagIndex = arguments.firstIndex(of: Self.launchArgument),
              arguments.indices.contains(flagIndex + 1) else { return nil }
        return URL(fileURLWithPath: arguments[flagIndex + 1], isDirectory: true)
    }
}
