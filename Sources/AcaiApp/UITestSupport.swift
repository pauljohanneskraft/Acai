import Foundation
import SwiftUI

/// Resolves a UI-test fixture's base directory from a launch argument, so `ProjectStore` can be
/// pointed at deterministic, disposable state instead of the real user's Application
/// Support/Documents directory. Fully inert (`resolveBaseDir()` returns `nil`) unless
/// `-AcaiUITestFixtureBaseDir <path>` is actually present — a real user's launch never carries it.
///
/// The path itself is resolved and staged by the test process, not this one: `App/AcaiUITests` (a
/// separate Xcode-project target — no shared internal API) copies its bundled `Fixtures/<name>`
/// resource to a fresh temporary directory before launch and passes that directory's absolute path
/// here (see `XCUIApplication.launchWithFixture(_:)` in `App/AcaiUITests/Support/Launch.swift`).
/// **The launch-argument name below and the one in `Launch.swift` must match** — they can't share
/// a constant across the SwiftPM package / Xcode-project boundary.
struct UITestFixtureResolver {
    static let launchArgument = "-AcaiUITestFixtureBaseDir"

    private let arguments: [String]

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.arguments = arguments
    }

    /// The staged fixture directory passed via `-AcaiUITestFixtureBaseDir <path>`, if any.
    func resolveBaseDir() -> URL? {
        resolve(Self.launchArgument)
    }

    static let gitHubRemoteLaunchArgument = "-AcaiUITestGitHubRemoteURL"

    /// A local git repository passed via `-AcaiUITestGitHubRemoteURL <path>`, to clone/fetch from
    /// instead of real github.com — see `FixtureGitHubRepositoryService`
    /// (`Sources/AcaiApp/GitHub/GitHubRepositoryService.swift`).
    func resolveGitHubRemoteURL() -> URL? {
        resolve(Self.gitHubRemoteLaunchArgument)
    }

    static let gitHubFastFixtureRootLaunchArgument = "-AcaiUITestGitHubFastFixtureRoot"

    /// Selects `FastFixtureGitHubRepositoryService` over the real-git `FixtureGitHubRepositoryService`.
    func resolveGitHubFastFixtureRoot() -> URL? {
        resolve(Self.gitHubFastFixtureRootLaunchArgument)
    }

    static let codebaseArtifactLaunchArgument = "-AcaiUITestCodebaseArtifact"

    /// Every `-AcaiUITestCodebaseArtifact <codebaseID> <path>` pair (repeatable) — see
    /// `CodebaseAnalyzingResolver`. A codebase with no entry still gets the real analyzer.
    func resolveCodebaseArtifactURLs() -> [UUID: URL] {
        var result: [UUID: URL] = [:]
        var index = arguments.startIndex
        while index < arguments.endIndex {
            defer { index += 1 }
            guard arguments[index] == Self.codebaseArtifactLaunchArgument,
                  arguments.indices.contains(index + 2),
                  let codebaseID = UUID(uuidString: arguments[index + 1])
            else { continue }
            result[codebaseID] = URL(fileURLWithPath: arguments[index + 2])
        }
        return result
    }

    static let colorSchemeLaunchArgument = "-AcaiUITestColorScheme"

    /// A forced `light`/`dark` appearance passed via `-AcaiUITestColorScheme <light|dark>`, so
    /// snapshot-test screenshots are deterministic regardless of the runner's or developer's own
    /// system appearance default (an unpinned mismatch flips nearly every pixel, not just the few
    /// percent of AA/font-hinting noise this suite already tolerates).
    func resolveColorScheme() -> ColorScheme? {
        guard let flagIndex = arguments.firstIndex(of: Self.colorSchemeLaunchArgument),
              arguments.indices.contains(flagIndex + 1) else { return nil }
        switch arguments[flagIndex + 1] {
        case "dark":
            return .dark
        case "light":
            return .light
        default:
            return nil
        }
    }

    private func resolve(_ flag: String) -> URL? {
        guard let flagIndex = arguments.firstIndex(of: flag),
              arguments.indices.contains(flagIndex + 1) else { return nil }
        return URL(fileURLWithPath: arguments[flagIndex + 1], isDirectory: true)
    }
}
