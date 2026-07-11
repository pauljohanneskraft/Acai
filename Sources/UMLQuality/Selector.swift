import UMLCore

/// A predicate that selects nodes (types) or modules in the relationship graph. Every facet is
/// optional and AND-combined: a node matches when *all* present facets match it. This is the shared
/// matching vocabulary for every rule kind. It names no language — `stereotype`/`annotation` are
/// resolved against the injected `LanguageConfiguration` map, never hardcoded markers.
public struct Selector: Codable, Equatable, Sendable {
    /// Exact module/target name, or a glob (`*`, `?`) over it.
    public var module: String?
    /// Glob (`*`, `?`) over a type's canonical id / qualified name.
    public var typeGlob: String?
    /// Required UML stereotype (e.g. `entity`, `repository`), resolved from annotations + kind.
    public var stereotype: String?
    /// Required annotation marker (normalized: `@Entity`, `jakarta.persistence.Entity` → `entity`).
    public var annotation: String?
    /// Minimum visibility the type must have (e.g. `public`).
    public var minimumAccess: AccessLevel?
    /// Required declaration kind (e.g. `class`) — lets a rule target only classes vs protocols.
    public var kind: TypeKind?
    /// Minimum member count — selects "god" types (e.g. classes with many members).
    public var minMembers: Int?
    /// Minimum nested-type depth — selects deeply nested types (scope a rule onto them).
    public var minNesting: Int?

    public init(
        module: String? = nil,
        typeGlob: String? = nil,
        stereotype: String? = nil,
        annotation: String? = nil,
        minimumAccess: AccessLevel? = nil,
        kind: TypeKind? = nil,
        minMembers: Int? = nil,
        minNesting: Int? = nil
    ) {
        self.module = module
        self.typeGlob = typeGlob
        self.stereotype = stereotype
        self.annotation = annotation
        self.minimumAccess = minimumAccess
        self.kind = kind
        self.minMembers = minMembers
        self.minNesting = minNesting
    }

    /// Lenient decoding so a rules file may omit any facet it doesn't use.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        module = try container.decodeIfPresent(String.self, forKey: .module)
        typeGlob = try container.decodeIfPresent(String.self, forKey: .typeGlob)
        stereotype = try container.decodeIfPresent(String.self, forKey: .stereotype)
        annotation = try container.decodeIfPresent(String.self, forKey: .annotation)
        minimumAccess = try container.decodeIfPresent(AccessLevel.self, forKey: .minimumAccess)
        kind = try container.decodeIfPresent(TypeKind.self, forKey: .kind)
        minMembers = try container.decodeIfPresent(Int.self, forKey: .minMembers)
        minNesting = try container.decodeIfPresent(Int.self, forKey: .minNesting)
    }

    /// Whether `node` satisfies every present facet.
    public func matches(_ node: GraphView.Node) -> Bool {
        if let module, !Glob(module).matches(node.module) { return false }
        if let typeGlob, !Glob(typeGlob).matches(node.id), !Glob(typeGlob).matches(node.qualifiedName) {
            return false
        }
        if let stereotype, node.stereotype != stereotype { return false }
        if let annotation, !node.annotations.contains(annotation.normalizedAnnotation) { return false }
        if let minimumAccess, node.access.visibilityRank < minimumAccess.visibilityRank { return false }
        if let kind, node.kind != kind { return false }
        if let minMembers, node.memberCount < minMembers { return false }
        if let minNesting, node.nestingDepth < minNesting { return false }
        return true
    }

    /// Whether this selector matches a module by name. Only the `module` facet is consulted;
    /// a selector with no `module` facet matches every module (used by whole-codebase budgets).
    public func matchesModule(named name: String) -> Bool {
        guard let module else { return true }
        return Glob(module).matches(name)
    }
}

/// A compiled `*`/`?` glob pattern, anchored to the whole string. A value you instantiate from a
/// pattern and ask `matches(_:)` — kept in-target (no regex dependency) so a malformed pattern can
/// never throw at evaluation time.
struct Glob: Sendable {
    private let pattern: [Character]

    init(_ pattern: String) {
        self.pattern = Array(pattern)
    }

    func matches(_ value: String) -> Bool {
        let v = Array(value)
        var pi = 0, vi = 0
        var star = -1, mark = 0
        while vi < v.count {
            if pi < pattern.count, pattern[pi] == "?" || pattern[pi] == v[vi] {
                pi += 1; vi += 1
            } else if pi < pattern.count, pattern[pi] == "*" {
                star = pi; mark = vi; pi += 1
            } else if star != -1 {
                pi = star + 1; mark += 1; vi = mark
            } else {
                return false
            }
        }
        while pi < pattern.count, pattern[pi] == "*" { pi += 1 }
        return pi == pattern.count
    }
}

extension String {
    /// Reduces an annotation marker to its bare comparable name, matching the normalization used by
    /// `TypeDeclaration.stereotype` (`@Entity`, `jakarta.persistence.Entity` → `entity`).
    var normalizedAnnotation: String {
        var name = trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("@") { name.removeFirst() }
        if let paren = name.firstIndex(of: "(") { name = String(name[..<paren]) }
        if let dot = name.lastIndex(of: ".") { name = String(name[name.index(after: dot)...]) }
        return name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
