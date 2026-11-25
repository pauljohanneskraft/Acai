import Foundation
import Testing
import AcaiCore
@testable import AcaiQuality

@Suite("Quality: Rules file version")
struct QualityRulesVersionTests {

    private func decode(_ json: String) throws -> QualityRules {
        try JSONDecoder().decode(QualityRules.self, from: Data(json.utf8))
    }

    @Test func aFileWithoutTheKeyReadsAsVersionOne() throws {
        let rules = try decode("{}")
        #expect(rules.version == 1)
    }

    @Test func theCurrentVersionIsAccepted() throws {
        let rules = try decode(#"{"version": \#(QualityRules.currentVersion), "includeGeneratedTypes": true}"#)
        #expect(rules.version == QualityRules.currentVersion)
        #expect(rules.includeGeneratedTypes)
    }

    @Test func aNewerVersionIsRejectedNamingBothVersions() {
        let newer = QualityRules.currentVersion + 1
        let error = #expect(throws: UnsupportedRulesVersion.self) {
            try decode(#"{"version": \#(newer)}"#)
        }
        #expect(error?.found == newer)
        #expect(error?.supported == QualityRules.currentVersion)
        let message = error?.errorDescription ?? ""
        #expect(message.contains("\(newer)"))
        #expect(message.contains("\(QualityRules.currentVersion)"))
    }

    @Test func aNewerVersionIsRejectedBeforeTheRestOfTheFileIsRead() {
        // The unreadable `budgets` must not mask the version, which is the real reason this fails.
        #expect(throws: UnsupportedRulesVersion.self) {
            try decode(#"{"version": \#(QualityRules.currentVersion + 1), "budgets": 5}"#)
        }
    }

    @Test func encodingWritesTheVersion() throws {
        let encoded = try JSONEncoder().encode(QualityRules())
        let fields = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        #expect(fields?["version"] as? Int == QualityRules.currentVersion)
    }

    @Test func theStarterDraftDeclaresTheCurrentVersion() {
        let artifact = CodeArtifact(metadata: .init(sourceLanguage: .swift), types: [], relationships: [])
        let graph = GraphView(
            artifact: artifact, languageResolver: LanguageConfigurationResolver(single: .test))
        #expect(StarterQualityRules(graph: graph).yaml.contains("version: \(QualityRules.currentVersion)"))
    }
}
