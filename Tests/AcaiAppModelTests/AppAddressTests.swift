import Foundation
import Testing
@testable import AcaiAppModel

/// `AppAddress`: the `acai://<kind>/<uuid>` deep link the app and the widget both speak.
@Suite("AppAddress")
struct AppAddressTests {
    private let id = UUID(uuidString: "7F6C1C1E-4F3A-4B7D-9C2E-1A2B3C4D5E6F")!

    @Test("Every kind round-trips through its URL")
    func everyKindRoundTrips() throws {
        for address in [AppAddress.project(id), .codebase(id), .diagram(id)] {
            #expect(AppAddress(url: address.url) == address)
        }
    }

    @Test("A codebase address spells out the scheme, host and id")
    func codebaseAddressSpelling() {
        #expect(AppAddress.codebase(id).url.absoluteString == "acai://codebase/\(id.uuidString)")
    }

    @Test("The host is matched case-insensitively, as a pasted link may not preserve case")
    func hostIsCaseInsensitive() {
        #expect(AppAddress(url: URL(string: "acai://CODEBASE/\(id.uuidString)")!) == .codebase(id))
    }

    @Test("A foreign scheme, unknown kind, non-UUID id, query or fragment is not an address")
    func malformedURLsAreRejected() {
        let rejected = [
            "https://codebase/\(id.uuidString)",
            "acai://finding/\(id.uuidString)",
            "acai://codebase/not-a-uuid",
            "acai://codebase/\(id.uuidString)/extra",
            "acai://codebase/\(id.uuidString)?x=1",
            "acai://codebase/\(id.uuidString)#x",
        ]
        for string in rejected {
            #expect(AppAddress(url: URL(string: string)!) == nil, "\(string) should not parse")
        }
    }
}
