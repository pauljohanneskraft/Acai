import Foundation

/// A codebase as of its last analysis, written by the app for a widget that can never see live state.
public struct CodebaseWidgetSnapshot: Codable, Equatable, Sendable, Identifiable {
    public var codebaseID: UUID
    public var codebaseName: String
    public var analysedAt: Date?
    public var analysedRevision: String?
    /// Meaningful only once `freshnessCheckedAt` is set.
    public var isOutOfDate = false
    public var freshnessCheckedAt: Date?
    public var typeCount: Int?
    public var findingCount: Int?
    public var criticalFindingCount: Int?
    public var hasParseErrors = false

    public var id: UUID { codebaseID }

    public var address: AppAddress { .codebase(codebaseID) }

    public init(
        codebaseID: UUID,
        codebaseName: String,
        analysedAt: Date? = nil,
        analysedRevision: String? = nil,
        isOutOfDate: Bool = false,
        freshnessCheckedAt: Date? = nil,
        typeCount: Int? = nil,
        findingCount: Int? = nil,
        criticalFindingCount: Int? = nil,
        hasParseErrors: Bool = false
    ) {
        self.codebaseID = codebaseID
        self.codebaseName = codebaseName
        self.analysedAt = analysedAt
        self.analysedRevision = analysedRevision
        self.isOutOfDate = isOutOfDate
        self.freshnessCheckedAt = freshnessCheckedAt
        self.typeCount = typeCount
        self.findingCount = findingCount
        self.criticalFindingCount = criticalFindingCount
        self.hasParseErrors = hasParseErrors
    }

    public var hasBeenAnalysed: Bool { analysedAt != nil }
}
