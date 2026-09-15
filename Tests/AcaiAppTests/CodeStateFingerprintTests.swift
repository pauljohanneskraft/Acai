import Foundation
import Testing
@testable import AcaiApp

@Suite("CodeStateFingerprint")
struct CodeStateFingerprintTests {
    @Test("Round-trips through Codable for the git case")
    func gitCaseRoundTrips() throws {
        let original = CodeStateFingerprint.git(headCommitSHA: "abc123", isDirty: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CodeStateFingerprint.self, from: data)
        #expect(decoded == original)
    }

    @Test("Round-trips through Codable for the file-system case")
    func fileSystemCaseRoundTrips() throws {
        let original = CodeStateFingerprint.fileSystem(
            latestModification: Date(), fileCount: 3, contentDigest: 42)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CodeStateFingerprint.self, from: data)
        #expect(decoded == original)
    }

    @Test("The two cases are never equal, even with matching numbers")
    func casesAreDistinct() {
        let git = CodeStateFingerprint.git(headCommitSHA: "0", isDirty: false)
        let fileSystem = CodeStateFingerprint.fileSystem(
            latestModification: .distantPast, fileCount: 0, contentDigest: 0)
        #expect(git != fileSystem)
    }
}
