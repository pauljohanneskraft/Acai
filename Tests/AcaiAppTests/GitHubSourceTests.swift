import Foundation
import Testing
@testable import AcaiApp

@Suite("GitHub source ref-kind persistence")
struct GitHubSourceTests {
    @Test func decodingLegacyJSONWithoutRefKindDefaultsToBranch() throws {
        let legacyJSON = Data("""
        {
            "owner": "acme",
            "repo": "widgets",
            "ref": "main",
            "lastSyncedCommitSHA": "abc123",
            "lastSyncedAt": 0
        }
        """.utf8)

        let source = try JSONDecoder().decode(GitHubSource.self, from: legacyJSON)

        #expect(source.refKind == .branch)
        #expect(source.ref == "main")
        #expect(source.lastSyncedCommitSHA == "abc123")
    }

    @Test func roundTripsTagKindThroughEncodeAndDecode() throws {
        let source = GitHubSource(owner: "acme", repo: "widgets", ref: "v1", refKind: .tag)

        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(GitHubSource.self, from: data)

        #expect(decoded == source)
        #expect(decoded.refKind == .tag)
    }

    @Test func qualifiedRefPrefixesBranchAndTagDifferently() {
        let branch = GitHubSource(owner: "acme", repo: "widgets", ref: "main", refKind: .branch)
        let tag = GitHubSource(owner: "acme", repo: "widgets", ref: "v1", refKind: .tag)

        #expect(branch.qualifiedRef == "heads/main")
        #expect(tag.qualifiedRef == "tags/v1")
    }

    @Test func gitHubRepositoryRefQualifiesTheSameWay() {
        let branch = GitHubRepositoryRef(owner: "acme", repo: "widgets", ref: "main", kind: .branch)
        let tag = GitHubRepositoryRef(owner: "acme", repo: "widgets", ref: "v1", kind: .tag)

        #expect(branch.qualifiedRef == "heads/main")
        #expect(tag.qualifiedRef == "tags/v1")
    }

    @Test func gitHubRefIDDisambiguatesSameNamedBranchAndTag() {
        let branch = GitHubRef(name: "v1", kind: .branch)
        let tag = GitHubRef(name: "v1", kind: .tag)

        #expect(branch.id != tag.id)
    }
}
