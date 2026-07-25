import XCTest
#if os(iOS)
import UIKit
#endif

/// An anchor purely so `Bundle(for:)` can resolve the UI test bundle — an Xcode-project target has
/// no SwiftPM `Bundle.module`, unlike `Tests/AcaiAppTests`.
private final class FixtureBundleAnchor {}

@MainActor
extension XCUIApplication {
    /// Rotates the simulator to landscape before a screenshot-golden test launches, iPad only — the
    /// wider canvas suits diagram/canvas content better there than portrait; iPhone and macOS
    /// goldens are unaffected. Call before `launchWithFixture` (not after) so the app launches
    /// already rotated, rather than racing an in-flight async rotation mid-test.
    func rotateToLandscapeOnIPad() {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        #endif
    }

    /// Ensures portrait before a test that assumes it (e.g. iPad's narrower, stack-based push/pop
    /// navigation with a `BackButton`) launches, iPad only. Device orientation is simulator-wide
    /// state, not scoped to one test's app launch — a test can't assume it starts in whatever
    /// orientation the *previous* test happened to leave the simulator in (confirmed empirically: a
    /// landscape rotation left over from a screenshot-golden test broke `GitHubAddCodebaseTests`'
    /// iPad `BackButton` expectation). Every non-landscape test declares this precondition itself,
    /// rather than relying on the landscape tests to clean up after themselves — that keeps each
    /// test correct regardless of run order.
    func rotateToPortraitOnIPad() {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .portrait
        }
        #endif
    }

    /// Launches the app pointed at a fresh, disposable copy of the named fixture
    /// (`Fixtures/<name>` in this UI test bundle) instead of the real user's persisted state.
    ///
    /// Fixture JSON may reference its own eventual on-disk location via the literal placeholder
    /// `$FIXTURE_ROOT` (its runtime path isn't known until after this copy, since it lands in a
    /// freshly generated temporary directory) — every occurrence in every file under the copy is
    /// substituted with the real destination path before launch.
    ///
    /// **The launch-argument name here must match `UITestFixtureResolver.launchArgument`**
    /// (`Sources/AcaiApp/UITestSupport.swift`) — the two can't share a constant across the SwiftPM
    /// package / Xcode-project boundary.
    ///
    /// `configure`, if given, runs after staging (so it can edit the staged fixture in place — e.g.
    /// turn a plain directory into a real git repo, or build a standalone "remote" repo alongside
    /// it) and before `launch()`, so it can also append further `launchArguments` (e.g.
    /// `-AcaiUITestGitHubRemoteURL`) that only make sense once its own setup ran.
    func launchWithFixture(
        _ name: String,
        configure: (XCUIApplication, URL) throws -> Void = { _, _ in },
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let testBundle = Bundle(for: FixtureBundleAnchor.self)
        guard let fixtureURL = testBundle.url(
            forResource: name, withExtension: nil, subdirectory: "Fixtures"
        ) else {
            XCTFail("Missing UI test fixture '\(name)' in the test bundle's Fixtures/ folder", file: file, line: line)
            return
        }

        #if os(macOS)
        // Not `FileManager.default.temporaryDirectory`: the macOS UI test runner is sandboxed (its
        // own `~/Library/Containers/de.kraftsoftware.Acai.UITests.xctrunner/Data/tmp/`), so that
        // call resolves *inside* the runner's private container — confirmed by inspecting the
        // actual path on disk. Handing that path to the unsandboxed app-under-test then has it read
        // fixture state out of a *different* app's sandbox container, which was confirmed (not just
        // suspected) to be the cause of a macOS UI test run prompting for an "access data from other
        // apps" permission at launch on every test function, regardless of code-signing identity:
        // switching to this plain, non-container path made the prompt disappear entirely across a
        // full 16-test run. The runner can't write to `/private/tmp` under its default sandbox
        // entitlements either — `App/AcaiUITests-macOS.entitlements` (wired via project.yml's
        // `CODE_SIGN_ENTITLEMENTS`) adds the one exception (`temporary-exception.files.absolute-
        // path.read-write` for `/private/tmp/`) needed to permit that.
        let tempRoot = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        #else
        let tempRoot = FileManager.default.temporaryDirectory
        #endif
        let destination = tempRoot
            .appendingPathComponent("AcaiUITestFixture-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.copyItem(at: fixtureURL, to: destination)
            try substituteFixtureRoot(in: destination)
            try configure(self, destination)
        } catch {
            XCTFail("Could not stage UI test fixture '\(name)': \(error)", file: file, line: line)
            return
        }

        launchArguments += [
            "-AcaiUITestFixtureBaseDir", destination.path,
            "-AcaiUITestColorScheme", defaultUITestColorScheme,
        ]
        launch()
    }

    /// The color scheme every UI test launch forces via `-AcaiUITestColorScheme`, so a screenshot
    /// golden's appearance never depends on the runner's or developer's own system default (see
    /// `UITestFixtureResolver.resolveColorScheme()`'s doc comment for the CI drift this fixes).
    /// Split across platforms rather than forcing one scheme everywhere, so both appearances get
    /// real screenshot coverage instead of only ever exercising one: macOS and iPhone run dark,
    /// iPad runs light. `Acai-iOSUITests` is one shared binary for both iPhone and iPad
    /// destinations, so the split is a runtime idiom check, not a per-target build setting.
    private var defaultUITestColorScheme: String {
        #if os(macOS)
        return "dark"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "light" : "dark"
        #endif
    }

    /// Replaces every `$FIXTURE_ROOT` occurrence in every file under `root` with `root`'s own
    /// path, in place.
    private func substituteFixtureRoot(in root: URL) throws {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return }
        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  let contents = try? String(contentsOf: fileURL, encoding: .utf8),
                  contents.contains("$FIXTURE_ROOT") else { continue }
            let substituted = contents.replacingOccurrences(of: "$FIXTURE_ROOT", with: root.path)
            try substituted.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}
