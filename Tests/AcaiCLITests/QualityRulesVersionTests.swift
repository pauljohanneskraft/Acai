import Foundation
import Testing
import AcaiQuality
@testable import AcaiCLI

@Suite("CLI: rules file version")
struct QualityRulesVersionTests {

    @Test func aFileWithoutTheKeyLoadsAsVersionOne() throws {
        let rules = try QualityRules.load(yaml: "cycles:\n  scope: modules\n")
        #expect(rules.version == 1)
        #expect(rules.cycles?.scope == .modules)
    }

    @Test func theCurrentVersionLoads() throws {
        let rules = try QualityRules.load(yaml: """
        version: \(QualityRules.currentVersion)
        budgets:
          - metric: distance
            max: 0.5
        """)
        #expect(rules.version == QualityRules.currentVersion)
        #expect(rules.budgets.count == 1)
    }

    @Test func aNewerVersionIsRefusedNamingBothVersions() {
        let newer = QualityRules.currentVersion + 1
        #expect {
            _ = try QualityRules.load(yaml: "version: \(newer)\n")
        } throws: { error in
            // Reported as the version problem it is, not as a generic decoding failure.
            let refusal = UnsupportedRulesVersion(found: newer, supported: QualityRules.currentVersion)
            return "\(error)" == refusal.description
        }
    }

    @Test func aNewerVersionIsRefusedEvenWhenTheRestOfTheFileIsValid() {
        let newer = QualityRules.currentVersion + 1
        #expect {
            _ = try QualityRules.load(yaml: """
            version: \(newer)
            cycles:
              scope: modules
            """)
        } throws: { error in
            let refusal = UnsupportedRulesVersion(found: newer, supported: QualityRules.currentVersion)
            return "\(error)" == refusal.description
        }
    }
}
