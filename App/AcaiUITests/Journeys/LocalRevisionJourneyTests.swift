import XCTest

/// #181: a local folder that is a git repository can be analysed at a revision from its history.
/// That the folder itself is left untouched is proven by `LocalRevisionAnalysisTests`; this proves
/// the picker reaches the analysis and says which revision is shown.
@MainActor
final class LocalRevisionJourneyTests: UIJourneyTestCase {
    func testALocalFolderCanBeAnalysedAtARevisionFromItsHistory() throws {
        let browser = launchSeeded(analysis: .parsed) { _, destination in
            let package = destination.appendingPathComponent("SampleSwiftPackage")
            try GitFixtureRepository(directory: package).commitInitialRevision(paths: Self.files(under: package))
        }
        let detail = ProjectDetailScreen(app: app)
        browser.projectRow(id: seeded.projectID).tap(
            "the seeded project's sidebar row", until: detail.codebaseRow(id: seeded.codebaseID)
        )
        let codebaseDetail = CodebaseDetailScreen(app: app)
        detail.codebaseRow(id: seeded.codebaseID).tap(
            "the seeded codebase's row", until: codebaseDetail.revisionPicker
        )

        codebaseDetail.analyse(at: "main")

        codebaseDetail.pinnedRevisionCaption.waitOrFail("the caption naming the analysed revision")
        let diagram = codebaseDetail.createDiagram(type: "class", as: ClassDiagramScreen.self)
        diagram.typeNode(named: "Base").waitOrFail("the Base type, read from the revision", timeout: .uiWork)
    }

    private static func files(under directory: URL) throws -> [String] {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        var paths: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            paths.append(String(url.standardizedFileURL.path.dropFirst(directory.standardizedFileURL.path.count + 1)))
        }
        return paths
    }
}
