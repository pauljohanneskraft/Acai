import Foundation

/// What a codebase looked like at the end of its last analysis, as the widget shows it. Written by
/// the app, read by the widget extension, which has no access to the codebase's folder and so can
/// only ever report this snapshot rather than live state.
public struct CodebaseWidgetSnapshot: Codable, Equatable, Sendable, Identifiable {
    public var codebaseID: UUID
    public var codebaseName: String
    /// `nil` for a codebase that has never been analysed — the widget offers analysing it instead
    /// of reporting an age it doesn't have.
    public var analysedAt: Date?
    /// The revision the analysis reflects, when it isn't the working tree (`Codebase.pinnedRevision`).
    public var analysedRevision: String?
    /// Whether the code had changed since the analysis, as of `freshnessCheckedAt`. The widget
    /// cannot recompute this itself, so an unchecked snapshot claims nothing.
    public var isOutOfDate = false
    /// When the app last compared the code against the analysis. `nil` means never.
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
