import Foundation
import Testing
import AcaiGit
@testable import AcaiApp

@Suite("Local revision lister")
struct LocalRevisionListerTests {
    private let directory = URL(fileURLWithPath: "/repo")

    @Test func listsBranchesAndCheckedOutRef() {
        let refs = [GitCheckout.Ref(name: "main", kind: .branch), GitCheckout.Ref(name: "v1.0", kind: .tag)]
        let lister = LocalRevisionLister(checkouts: FakeCheckoutInspector(refs: refs, currentRef: "main"))

        #expect(lister.revisions(in: directory) == LocalRevisions(refs: refs, checkedOut: "main"))
    }

    @Test func aFolderOutsideAnyRepositoryHasNoRevisions() {
        let lister = LocalRevisionLister(checkouts: FakeCheckoutInspector())

        #expect(lister.revisions(in: directory) == nil)
    }

    @Test func anUnreadableHeadStillListsTheBranches() {
        let refs = [GitCheckout.Ref(name: "main", kind: .branch)]
        let lister = LocalRevisionLister(checkouts: FakeCheckoutInspector(refs: refs))

        #expect(lister.revisions(in: directory) == LocalRevisions(refs: refs, checkedOut: nil))
    }
}
