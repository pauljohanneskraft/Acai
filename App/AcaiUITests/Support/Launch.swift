import XCTest
#if os(iOS)
import UIKit
#endif

/// So `Bundle(for:)` can resolve the UI test bundle — an Xcode-project target has no SwiftPM
/// `Bundle.module`, unlike `Tests/AcaiAppTests`.
private final class FixtureBundleAnchor {}

@MainActor
extension XCUIApplication {
    /// Call before `launchWithFixture` (not after) so the app launches already rotated, rather than
    /// racing an in-flight async rotation mid-test.
    func rotateToLandscapeOnIPad() {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        #endif
    }

    /// Device orientation is simulator-wide state, not scoped to one test's app launch, so a test
    /// can't assume it starts in whatever orientation the *previous* test left the simulator in —
    /// every non-landscape test declares this precondition itself rather than relying on landscape
    /// tests to clean up after themselves.
    func rotateToPortraitOnIPad() {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .portrait
        }
        #endif
    }

    /// Launches the app pointed at a fresh, disposable copy of the named fixture
    /// (`Fixtures/<name>` in this UI test bundle) instead of the real user's persisted state.
    /// Fixture JSON may reference its own eventual on-disk location via the literal placeholder
    /// `$FIXTURE_ROOT`; every occurrence in every file under the copy is substituted with the real
    /// destination path before launch.
    ///
    /// Everything is handed over through `launchEnvironment`; see `UITestFixtureResolver`
    /// (`Sources/AcaiApp/UITestSupport.swift`) for why never through `launchArguments`, and for the
    /// variable names, which the two can't share a constant for across the SwiftPM package /
    /// Xcode-project boundary.
    /// `language` runs the app in that localization. It has to go through `launchArguments` — the
    /// `AppleLanguages` default is what decides `Locale.current`, and nothing in the environment
    /// reaches it — so it is passed as a `-key value` pair, which `assertLaunchArgumentsAreDefaults`
    /// permits.
    func launchWithFixture(
        _ name: String,
        language: String? = nil,
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
        // Not `FileManager.default.temporaryDirectory`: that resolves inside the sandboxed UI test
        // runner's own container, and handing that path to the app-under-test triggers an "access
        // data from other apps" prompt at every launch. `/private/tmp` avoids that.
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

        launchEnvironment["ACAI_UITEST_FIXTURE_BASE_DIR"] = destination.path
        launchEnvironment["ACAI_UITEST_COLOR_SCHEME"] = defaultUITestColorScheme
        if let language {
            launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", language]
        }
        assertLaunchArgumentsAreDefaults(file: file, line: line)
        launch()
        #if os(macOS)
        // `launch()` doesn't guarantee frontmost on macOS — that's a separate driver-side request.
        activate()
        // Absorbs this Debug build's cold-launch cost once, instead of it eating per-test timeouts.
        guard windows.firstMatch.waitForExistence(timeout: 30) else {
            let tree = XCTAttachment(string: debugDescription)
            tree.name = "no window after launch — element tree"
            tree.lifetime = .keepAlways
            XCTContext.runActivity(named: "No window appeared") { $0.add(tree) }
            XCTFail("No window appeared after launch", file: file, line: line)
            return
        }
        #endif
    }

    /// Guards the reason everything goes through `launchEnvironment` — see `UITestFixtureResolver`:
    /// a launch argument outside a `-key value` pair is read as a file to open, and an app launched
    /// to open files comes up with a menu bar and no window at all. `UserDefaults` overrides, which
    /// *are* `-key value` pairs, are the one thing that has to travel this way.
    private func assertLaunchArgumentsAreDefaults(file: StaticString, line: UInt) {
        let keys = stride(from: 0, to: launchArguments.count, by: 2).map { launchArguments[$0] }
        XCTAssertTrue(
            launchArguments.count.isMultiple(of: 2) && keys.allSatisfy { $0.hasPrefix("-") },
            "UI-test configuration must go through launchEnvironment, or a `-key value` UserDefaults "
            + "override (got \(launchArguments)) — see UITestFixtureResolver",
            file: file, line: line
        )
    }

    /// Encodes a repeatable multi-field value into one environment variable. Mirrors the decoding in
    /// `UITestFixtureResolver` (`Sources/AcaiApp/UITestSupport.swift`).
    func environmentRecords(_ records: [[String]]) -> String {
        records.map { $0.joined(separator: "\t") }.joined(separator: "\n")
    }

    /// Forced via `ACAI_UITEST_COLOR_SCHEME` so a screenshot golden's appearance never depends on the
    /// runner's system default. Split across platforms so both appearances get real coverage:
    /// macOS and iPhone run dark, iPad runs light.
    private var defaultUITestColorScheme: String {
        #if os(macOS)
        return "dark"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "light" : "dark"
        #endif
    }

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
