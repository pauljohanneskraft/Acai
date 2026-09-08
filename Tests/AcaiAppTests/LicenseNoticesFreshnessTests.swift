import Foundation
import Testing
@testable import AcaiApp

/// `Licenses.json` is a manually regenerated snapshot (`Scripts/generate_licenses.sh`) of
/// `Package.resolved`, not something the build derives automatically. Nothing stops a dependency
/// bump from landing without a regeneration, so the shown notices silently describe a package set
/// that no longer matches what ships. This compares the two directly — bypassing `LicenseCatalog`'s
/// bundle lookup, the same way `LocalizationCatalogTests` reads its catalog straight off disk — so
/// staleness fails a test rather than only showing up as a legal problem later.
@Suite("License notices freshness")
struct LicenseNoticesFreshnessTests {

    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test func everyResolvedDependencyHasAMatchingLicenseEntryAtItsPinnedRevision() throws {
        let pinsByIdentity = try resolvedPins()
        let dependenciesByName = try shippedLicenseDependencies()

        let missing = Set(pinsByIdentity.keys).subtracting(dependenciesByName.keys)
        #expect(
            missing.isEmpty,
            "Package.resolved has dependencies with no Licenses.json entry: \(missing.sorted()). "
                + "Run Scripts/generate_licenses.sh and commit the result."
        )

        let stale = Set(dependenciesByName.keys).subtracting(pinsByIdentity.keys)
        #expect(
            stale.isEmpty,
            "Licenses.json has entries for dependencies no longer in Package.resolved: \(stale.sorted()). "
                + "Run Scripts/generate_licenses.sh and commit the result."
        )

        for (identity, pin) in pinsByIdentity {
            guard let dependency = dependenciesByName[identity] else { continue }
            #expect(
                dependency.revision == pin.revision,
                "Licenses.json pins \(identity) at \(dependency.revision), but Package.resolved now "
                    + "resolves it to \(pin.revision). Run Scripts/generate_licenses.sh and commit the result."
            )
        }
    }

    private func resolvedPins() throws -> [String: ResolvedPin] {
        let url = repoRoot.appendingPathComponent("Package.resolved")
        let data = try Data(contentsOf: url)
        let pins = try JSONDecoder().decode(ResolvedPackage.self, from: data).pins
        return Dictionary(uniqueKeysWithValues: pins.map { ($0.identity, $0) })
    }

    private func shippedLicenseDependencies() throws -> [String: DependencyLicense] {
        let url = repoRoot.appendingPathComponent("Sources/AcaiApp/Resources/Licenses.json")
        let data = try Data(contentsOf: url)
        let dependencies = try JSONDecoder().decode(LicenseDocument.self, from: data).dependencies
        return Dictionary(uniqueKeysWithValues: dependencies.map { ($0.name, $0) })
    }

    private struct ResolvedPackage: Decodable {
        let pins: [ResolvedPin]
    }

    private struct ResolvedPin: Decodable {
        let identity: String
        let revision: String

        private enum CodingKeys: String, CodingKey {
            case identity, state
        }

        private enum StateCodingKeys: String, CodingKey {
            case revision
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            identity = try container.decode(String.self, forKey: .identity)
            let state = try container.nestedContainer(keyedBy: StateCodingKeys.self, forKey: .state)
            revision = try state.decode(String.self, forKey: .revision)
        }
    }
}
