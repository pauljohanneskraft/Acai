import Foundation
import Testing
import AcaiGit
@testable import AcaiApp

@Suite("Compare panel state")
struct ComparePanelStateTests {
    private let main = GitCheckout.Ref(name: "main", kind: .branch)
    private let release = GitCheckout.Ref(name: "v1.0", kind: .tag)
    private let request = ChangeRequest(
        number: 7, title: "Add widget", authorLogin: "dev", baseRef: "main", headRef: "feature", state: "open")

    @Test func listsHeadThenChangeRequestsThenRefsThenCustom() {
        let state = ComparePanelState(refs: [main, release], changeRequests: [request])

        #expect(state.rows == [.head, .changeRequest(request), .ref(main), .ref(release), .custom])
    }

    @Test func aRefNamedHEADIsCoveredByTheHeadRow() {
        let state = ComparePanelState(refs: [GitCheckout.Ref(name: "HEAD", kind: .branch), main])

        #expect(state.rows == [.head, .ref(main), .custom])
    }

    @Test func selectsTheRowMatchingTheComparisonRefs() {
        var state = ComparePanelState(refs: [main], changeRequests: [request])
        #expect(state.selectedRow == nil)

        state.comparisonGitRef = "HEAD"
        #expect(state.selectedRow == .head)

        state.comparisonGitRef = "main"
        #expect(state.selectedRow == .ref(main))

        state.comparisonGitRef = "abc123"
        #expect(state.selectedRow == .custom)

        state.comparisonGitRef = "feature"
        state.comparisonBaseRef = "main"
        #expect(state.selectedRow == .changeRequest(request))

        state.comparisonBaseRef = "develop"
        #expect(state.selectedRow == nil)
    }

    @Test func statusFollowsTheLoadedSides() {
        var state = ComparePanelState()
        #expect(state.status == nil)

        state.comparisonGitRef = "main"
        #expect(state.status == .loading)

        state.hasOldArtifact = true
        #expect(state.status == .loaded)
        #expect(state.isFullyLoaded)

        state.comparisonBaseRef = "develop"
        #expect(state.status == .loading)

        state.hasNewArtifact = true
        #expect(state.status == .loaded)

        state.error = "Couldn't read main"
        #expect(state.status == .failed("Couldn't read main"))
    }
}
