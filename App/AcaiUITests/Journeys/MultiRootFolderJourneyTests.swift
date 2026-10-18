import XCTest

/// Pointing the app at a folder that holds several projects asks what to do with them instead of
/// silently making one codebase. Both answers are covered in one launch: the folder is split into a
/// codebase per project, then the same folder is added again as a single combined codebase.
///
/// The folder is built here rather than bundled as a fixture resource: two throwaway Swift packages
/// are all the walk needs, and staging them outside `Fixtures/seeded` keeps the shared fixture — and
/// every golden taken from it — untouched.
@MainActor
final class MultiRootFolderJourneyTests: UIJourneyTestCase {
    func testAFolderOfSeveralProjectsIsSplitOrCombinedOnRequest() throws {
        let browser = launchSeeded(configure: { app, destination in
            let workspace = destination
                .deletingLastPathComponent()
                .appendingPathComponent("MultiRootWorkspace", isDirectory: true)
            try? FileManager.default.removeItem(at: workspace)
            for name in ["Alpha", "Beta"] {
                let sources = workspace.appendingPathComponent("\(name)/Sources/\(name)", isDirectory: true)
                try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
                try "// swift-tools-version:6.0\n".write(
                    to: workspace.appendingPathComponent("\(name)/Package.swift"),
                    atomically: true, encoding: .utf8)
                try "struct \(name)Service {}\n".write(
                    to: sources.appendingPathComponent("\(name).swift"), atomically: true, encoding: .utf8)
            }
            app.launchEnvironment["ACAI_UITEST_LOCAL_FOLDER"] = workspace.path
        })

        let detail = ProjectDetailScreen(app: app)
        browser.projectRow(id: seeded.projectID).tap(
            "the seeded project's sidebar row", until: detail.codebaseRow(id: seeded.codebaseID))

        // One codebase per project: both roots arrive checked, so Add needs no further choice.
        let sheet = NewCodebaseSheetScreen(app: app)
        detail.tapAddCodebase()
        sheet.chooseStagedFolder()
        sheet.rootToggle("Alpha").waitOrFail("the Alpha project's checkbox")
        sheet.rootToggle("Beta").waitOrFail("the Beta project's checkbox")
        sheet.add()

        detail.codebaseRow(named: "Alpha").waitOrFail("the Alpha codebase's row")
        detail.codebaseRow(named: "Beta").waitOrFail("the Beta codebase's row")

        // The same folder again, combined this time: one codebase under the typed name.
        detail.tapAddCodebase()
        sheet.chooseStagedFolder()
        sheet.enterLocalName("Everything")
        sheet.flip(sheet.combineRootsToggle, "the Combine into one codebase toggle")
        sheet.add()

        detail.codebaseRow(named: "Everything").waitOrFail("the combined codebase's row")
    }
}
