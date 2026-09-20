/// What a type's own members tell a body walker about the names it meets: which identifiers are
/// stored properties, which of those have a provable type, and what an unqualified same-type method
/// call returns.
///
/// In `AcaiCore` rather than `AcaiTreeSitter` because it reads `[Member]` and names no `Node`.
public struct MemberIndex: Sendable {

    /// Stored properties with a determinable type — call-site resolution needs the type.
    public let propertyTypes: [String: String]

    /// **All** property names, including untyped ones (e.g. Python's `self.x = …`). Field-read
    /// capture filters by name only, so it needs the full set, not just the typed subset.
    public let propertyNames: Set<String>

    /// Unambiguous overloads only, so a local initialized from a same-type method call
    /// (`let x = compute()`) can have its type inferred the way a direct construction already is.
    public let methodReturnTypes: [String: String]

    public init(members: [Member]) {
        var propertyTypes: [String: String] = [:]
        var propertyNames: Set<String> = []
        var returnTypes = UnambiguousTypeNames()

        for member in members {
            switch member.kind {
            case .property:
                propertyNames.insert(member.name)
                if let typeName = member.type?.name {
                    propertyTypes[member.name] = typeName
                }
            case .method:
                if let typeName = member.type?.name {
                    returnTypes.record(typeName, for: member.name)
                }
            default:
                break
            }
        }

        self.propertyTypes = propertyTypes
        self.propertyNames = propertyNames
        self.methodReturnTypes = returnTypes.resolved
    }
}

/// Name → type name, keeping only names with exactly one candidate.
///
/// The rule every extractor applies to overloads: guessing one of several return types seeds a
/// local with the wrong type and produces a confidently wrong call edge, so an ambiguous name is
/// dropped instead. Written once here because the collapse itself is identical whether the
/// candidates came from `[Member]` or straight off the grammar's nodes.
public struct UnambiguousTypeNames: Sendable {

    private var candidates: [String: Set<String>] = [:]

    public init() {}

    public mutating func record(_ typeName: String, for name: String) {
        candidates[name, default: []].insert(typeName)
    }

    public var resolved: [String: String] {
        candidates.compactMapValues { $0.count == 1 ? $0.first : nil }
    }
}
