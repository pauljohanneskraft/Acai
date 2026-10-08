import Foundation
import Testing
@testable import AcaiAppModel

/// What an address resolves to in the app is `AppAddressResolutionTests`.
@Suite("App addresses")
struct AppAddressTests {
    @Test(arguments: [AppAddress.project(UUID()), .codebase(UUID()), .diagram(UUID())])
    func urlRoundTrips(_ address: AppAddress) {
        #expect(AppAddress(url: address.url) == address)
    }

    @Test func urlHasTheDocumentedShape() {
        let id = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        #expect(AppAddress.codebase(id).url.absoluteString == "acai://codebase/22222222-2222-2222-2222-222222222222")
    }

    @Test func parsingIgnoresTheCaseOfSchemeKindAndID() throws {
        let url = try #require(URL(string: "ACAI://Diagram/33333333-3333-3333-3333-33333333333a"))
        #expect(AppAddress(url: url) == .diagram(UUID(uuidString: "33333333-3333-3333-3333-33333333333A")!))
    }

    @Test(arguments: [
        "https://codebase/22222222-2222-2222-2222-222222222222",
        "acai://codebase/not-a-uuid",
        "acai://codebase/22222222-2222-2222-2222-222222222222/extra",
        "acai://codebase",
        "acai://repository/22222222-2222-2222-2222-222222222222",
        "acai://codebase/22222222-2222-2222-2222-222222222222?x=1",
        "acai://codebase/22222222-2222-2222-2222-222222222222#x"
    ])
    func malformedURLsAreRejected(_ string: String) throws {
        let url = try #require(URL(string: string))
        #expect(AppAddress(url: url) == nil)
    }
}
