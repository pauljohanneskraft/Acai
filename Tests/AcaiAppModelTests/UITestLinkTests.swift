import Foundation
import Testing
import AcaiAppModel

@Suite("UITestLink")
struct UITestLinkTests {
    private let id = UUID()

    @Test func selectionRoutesNameTheirTarget() throws {
        #expect(UITestLink(url: try url("acai://uitest/findings/\(id)")) == .findings(projectID: id))
        #expect(UITestLink(url: try url("acai://uitest/query/\(id)")) == .query(codebaseID: id))
        let remote = "https://example.com/org/repo.git"
        let encoded = try #require(remote.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        #expect(UITestLink(url: try url("acai://uitest/repository?url=\(encoded)"))
            == .repository(remoteURL: try url(remote)))
    }

    @Test func presentationRoutesNameWhatTheyPresent() throws {
        #expect(UITestLink(url: try url("acai://uitest/present/settings")) == .present(.settings))
        #expect(UITestLink(url: try url("acai://uitest/present/keyboard-shortcuts")) == .present(.keyboardShortcuts))
        #expect(UITestLink(url: try url("acai://uitest/present/quick-open")) == .present(.quickOpen))
        #expect(UITestLink(url: try url("acai://uitest/present/new-project")) == .present(.newProject))
        #expect(UITestLink(url: try url("acai://uitest/present/new-codebase/\(id)"))
            == .present(.newCodebase(projectID: id)))
        #expect(UITestLink(url: try url("acai://uitest/present/delete-project/\(id)")) == .present(.deleteProject(id)))
        #expect(UITestLink(url: try url("acai://uitest/present/delete-codebase/\(id)"))
            == .present(.deleteCodebase(id)))
    }

    @Test func anythingElseIsNotATestLink() throws {
        for text in [
            "acai://project/\(id)",
            "other://uitest/findings/\(id)",
            "acai://uitest/findings/not-a-uuid",
            "acai://uitest/findings/\(id)/extra",
            "acai://uitest/present/settings/extra",
            "acai://uitest/present/delete-codebase",
            "acai://uitest/unknown",
            "acai://uitest/repository"
        ] {
            #expect(UITestLink(url: try url(text)) == nil, "\(text)")
        }
    }

    private func url(_ text: String) throws -> URL {
        try #require(URL(string: text))
    }
}
