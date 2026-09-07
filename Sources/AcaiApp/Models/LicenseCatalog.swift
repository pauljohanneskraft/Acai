import Foundation

struct DependencyLicense: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    /// `nil` for a branch pin — `Package.resolved` reports a branch name instead of a version there.
    let version: String?
    let revision: String
    let location: String
    let licenseIdentifier: String
    let licenseText: String
    let notes: String?
}

struct LicenseDocument: Codable {
    let schemaVersion: Int
    let generatedAt: String
    let dependencies: [DependencyLicense]
}

struct LicenseCatalog {
    private let bundle: Bundle
    private let currentSchemaVersion = 1

    init(bundle: Bundle = .module) {
        self.bundle = bundle
    }

    enum CatalogError: LocalizedError {
        case resourceMissing
        case unsupportedSchemaVersion(Int)

        var errorDescription: String? {
            switch self {
            case .resourceMissing:
                return String(localized: .app("Error.LicenseCatalog.ResourceMissing"))
            case .unsupportedSchemaVersion(let version):
                return String(localized: .app("Error.LicenseCatalog.UnsupportedSchemaVersion \(version)"))
            }
        }
    }

    /// Touches disk — run off the main actor.
    func load() throws -> [DependencyLicense] {
        guard let url = bundle.url(forResource: "Licenses", withExtension: "json") else {
            throw CatalogError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        let document = try JSONDecoder().decode(LicenseDocument.self, from: data)
        guard document.schemaVersion == currentSchemaVersion else {
            throw CatalogError.unsupportedSchemaVersion(document.schemaVersion)
        }
        return document.dependencies
    }
}
