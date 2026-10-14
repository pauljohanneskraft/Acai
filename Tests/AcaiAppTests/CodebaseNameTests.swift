import Foundation
import Testing
@testable import AcaiApp

@Suite("Codebase names", .timeLimit(.minutes(1)))
struct CodebaseNameTests {
    @Test func aRemoteIsNamedAfterItsLastPathComponentWithoutDotGit() {
        #expect(RemoteRepositoryName(remoteURL: URL(string: "https://example.com/team/widgets.git")!).value
            == "widgets")
        #expect(RemoteRepositoryName(remoteURL: URL(string: "https://example.com/team/widgets")!).value == "widgets")
        #expect(RemoteRepositoryName(remoteURL: URL(fileURLWithPath: "/tmp/TeamRemote")).value == "TeamRemote")
    }

    /// Only a `.git` suffix is dropped — a name that merely has a dot in it keeps all of it.
    @Test func anExtensionThatIsNotDotGitIsKept() {
        #expect(RemoteRepositoryName(remoteURL: URL(string: "https://example.com/team/widgets.v2")!).value
            == "widgets.v2")
    }

    @Test func anAddressWithoutAPathFallsBackToItsHost() {
        #expect(RemoteRepositoryName(remoteURL: URL(string: "https://example.com")!).value == "example.com")
        #expect(RemoteRepositoryName(remoteURL: URL(string: "https://example.com/")!).value == "example.com")
    }

    @Test func aNameTheProjectAlreadyUsesIsNumbered() {
        #expect(UniqueCodebaseName(proposed: "widgets", taken: []).value == "widgets")
        #expect(UniqueCodebaseName(proposed: "widgets", taken: ["gadgets"]).value == "widgets")
        #expect(UniqueCodebaseName(proposed: "widgets", taken: ["widgets"]).value == "widgets 2")
        #expect(UniqueCodebaseName(proposed: "widgets", taken: ["widgets", "widgets 2"]).value == "widgets 3")
    }

    /// The suffix skips a number already in use rather than stopping at the first gap it finds.
    @Test func anAlreadyNumberedNameKeepsCounting() {
        #expect(UniqueCodebaseName(proposed: "widgets", taken: ["widgets", "widgets 3"]).value == "widgets 2")
        #expect(
            UniqueCodebaseName(proposed: "widgets", taken: ["widgets", "widgets 2", "widgets 3"]).value
                == "widgets 4")
    }
}
