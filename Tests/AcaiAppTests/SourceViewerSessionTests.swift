import Foundation
import Testing
@testable import AcaiApp

/// Closing the viewer deletes a directory, so what it may delete needs to be a decision with a test
/// rather than a condition inside a dismissal handler: deleting the working tree's own folder would
/// take the user's source with it.
@Suite("Source viewer session")
struct SourceViewerSessionTests {
    private let workingTreeFile = URL(fileURLWithPath: "/Users/someone/Project/Sources/App/Widget.swift")

    @Test func aFileReadFromTheWorkingTreeIsNeverDeleted() {
        let session = SourceViewerSession(isPinnedRevision: false, shownURL: workingTreeFile)

        #expect(session.temporaryDirectoryToRemove == nil)
    }

    @Test func aFileExtractedFromHistoryTakesItsTemporaryDirectory() {
        let extracted = URL(fileURLWithPath: "/tmp/acai-revision-ABC/Widget.swift")
        let session = SourceViewerSession(isPinnedRevision: true, shownURL: extracted)

        #expect(session.temporaryDirectoryToRemove?.path == "/tmp/acai-revision-ABC")
    }

    @Test func nothingIsDeletedWhenNoFileWasShown() {
        #expect(SourceViewerSession(isPinnedRevision: true, shownURL: nil).temporaryDirectoryToRemove == nil)
        #expect(SourceViewerSession(isPinnedRevision: false, shownURL: nil).temporaryDirectoryToRemove == nil)
    }
}
