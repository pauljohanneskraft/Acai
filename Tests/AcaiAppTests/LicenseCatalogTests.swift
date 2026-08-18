import Foundation
import Testing
@testable import AcaiApp

struct LicenseCatalogTests {
    @Test func decodesTheBundledCatalog() throws {
        let dependencies = try LicenseCatalog().load()
        #expect(!dependencies.isEmpty)
    }

    @Test func everyEntryHasTheExpectedShape() throws {
        let dependencies = try LicenseCatalog().load()
        for dependency in dependencies {
            #expect(!dependency.name.isEmpty)
            #expect(!dependency.revision.isEmpty)
            #expect(!dependency.location.isEmpty)
            #expect(!dependency.licenseIdentifier.isEmpty)
            #expect(!dependency.licenseText.isEmpty)
        }
    }

    @Test func libgit2IsPresentWithGPLAndForkAttribution() throws {
        let dependencies = try LicenseCatalog().load()
        let libgit2 = try #require(dependencies.first { $0.name == "libgit2" })
        #expect(libgit2.licenseIdentifier == "GPL-2.0-only")
        #expect(libgit2.licenseText.contains("GNU GENERAL PUBLIC LICENSE"))
        let notes = try #require(libgit2.notes)
        #expect(notes.contains("https://github.com/libgit2/libgit2"))
    }

    @Test func throwsResourceMissingWhenTheBundleHasNoLicensesJSON() throws {
        let tempBundle = try makeBundle(licensesJSON: nil)
        #expect {
            try LicenseCatalog(bundle: tempBundle.bundle).load()
        } throws: { error in
            guard case LicenseCatalog.CatalogError.resourceMissing = error else { return false }
            return true
        }
    }

    @Test func throwsOnAnUnsupportedSchemaVersion() throws {
        let tempBundle = try makeBundle(licensesJSON: """
        {"schemaVersion": 999, "generatedAt": "2026-01-01T00:00:00Z", "dependencies": []}
        """)
        #expect {
            try LicenseCatalog(bundle: tempBundle.bundle).load()
        } throws: { error in
            guard case LicenseCatalog.CatalogError.unsupportedSchemaVersion(let version) = error else { return false }
            return version == 999
        }
    }

    @Test func decodesAWellFormedDocument() throws {
        let tempBundle = try makeBundle(licensesJSON: """
        {
            "schemaVersion": 1,
            "generatedAt": "2026-01-01T00:00:00Z",
            "dependencies": [
                {
                    "name": "example",
                    "version": "1.0.0",
                    "revision": "abc123",
                    "location": "https://example.com/example.git",
                    "licenseIdentifier": "MIT",
                    "licenseText": "MIT License text",
                    "notes": null
                }
            ]
        }
        """)
        let dependencies = try LicenseCatalog(bundle: tempBundle.bundle).load()
        #expect(dependencies.count == 1)
        #expect(dependencies[0].name == "example")
        #expect(dependencies[0].version == "1.0.0")
        #expect(dependencies[0].licenseIdentifier == "MIT")
        #expect(dependencies[0].notes == nil)
    }

    private func makeBundle(licensesJSON: String?) throws -> TemporaryBundle {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let licensesJSON {
            try licensesJSON.write(
                to: directory.appendingPathComponent("Licenses.json"), atomically: true, encoding: .utf8)
        }
        let bundle = try #require(Bundle(url: directory))
        return TemporaryBundle(directory: directory, bundle: bundle)
    }
}

private final class TemporaryBundle {
    let bundle: Bundle
    private let directory: URL

    init(directory: URL, bundle: Bundle) {
        self.directory = directory
        self.bundle = bundle
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}
