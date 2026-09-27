import Foundation
import Testing

/// A journey costs its own launch on three platforms, and every shard's wall clock is dominated by
/// that rather than by the behaviour under test — so the suite's size is budgeted rather than left to
/// grow one reasonable-looking addition at a time.
///
/// Reaching this budget is not a reason to raise it. Prove the behaviour in a unit test and delete
/// the journey, or fold the new one into a journey that already reaches the same screen. Lowering the
/// number as journeys go is the point; raising it needs a reason in the commit that does it.
@Suite("Journey budget")
struct JourneyBudgetTests {
    private static let budget = 35

    private var journeysDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/AcaiUITests/Journeys")
    }

    @Test func theSuiteStaysWithinItsJourneyBudget() throws {
        let files = try FileManager.default.contentsOfDirectory(at: journeysDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        let counts = try files.map { (name: $0.lastPathComponent, tests: try testMethodCount(in: $0)) }
        let total = counts.reduce(0) { $0 + $1.tests }

        #expect(
            total <= Self.budget,
            """
            \(total) journeys against a budget of \(Self.budget). Prove the new behaviour in a unit \
            test, or fold it into a journey that already opens the same screen — see this suite's \
            documentation before changing the budget.
            """
        )
        #expect(!counts.contains { $0.tests == 0 }, "a journey file with no test method is dead weight")
    }

    private func testMethodCount(in url: URL) throws -> Int {
        try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .count { $0.trimmingCharacters(in: .whitespaces).hasPrefix("func test") }
    }
}
