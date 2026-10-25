import AcaiCore
import AppIntents
import Foundation

/// A declared type in one codebase; its static strings live in the app targets' `AppIntents.xcstrings`.
struct TypeEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Intent.TypeEntity.TypeName", table: "AppIntents"))
    static let defaultQuery = TypeEntityQuery()

    /// A type id alone is only unique within one artifact.
    struct Address: Hashable, Sendable {
        let codebaseID: UUID
        let typeID: String

        var id: String { "\(codebaseID.uuidString)/\(typeID)" }

        init(codebaseID: UUID, typeID: String) {
            self.codebaseID = codebaseID
            self.typeID = typeID
        }

        init?(_ id: String) {
            let parts = id.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let codebaseID = UUID(uuidString: String(parts[0])), !parts[1].isEmpty
            else { return nil }
            self.init(codebaseID: codebaseID, typeID: String(parts[1]))
        }
    }

    let id: String

    @Property(title: LocalizedStringResource("Intent.TypeEntity.QualifiedName", table: "AppIntents"))
    var qualifiedName: String

    /// `file:line`, absent for a type no parser gave an extent for.
    @Property(title: LocalizedStringResource("Intent.TypeEntity.Location", table: "AppIntents"))
    var location: String?

    init(address: Address, qualifiedName: String, location: String?) {
        self.id = address.id
        self.qualifiedName = qualifiedName
        self.location = location
    }

    /// Never localized: a type name and a path are what the parser read, not chrome.
    var displayRepresentation: DisplayRepresentation {
        guard let location else { return DisplayRepresentation(title: "\(qualifiedName)") }
        return DisplayRepresentation(title: "\(qualifiedName)", subtitle: "\(location)")
    }
}

extension TypeEntity {
    init(_ dependent: ImpactAnalysis.Dependent, in codebaseID: UUID) {
        self.init(
            address: Address(codebaseID: codebaseID, typeID: dependent.id),
            qualifiedName: dependent.qualifiedName,
            location: dependent.location?.intentDisplay)
    }

    init(_ type: TypeDeclaration, in codebaseID: UUID) {
        self.init(
            address: Address(codebaseID: codebaseID, typeID: type.id),
            qualifiedName: type.qualifiedName,
            location: type.location?.intentDisplay)
    }
}

extension SourceLocation {
    /// The `file:line` form every Acai surface prints a location as.
    var intentDisplay: String { "\(filePath):\(line)" }
}

struct TypeEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [TypeEntity] {
        try await CodebaseInsights(store: .app).types(identifiedBy: identifiers)
    }
}
