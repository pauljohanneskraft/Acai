import UMLCore

/// Python-specific semantic reasoning that isn't expressible as a query-time keyword lookup: access
/// by naming convention (no access keywords exist), decorator-driven member kind, and Enum/ABC/
/// Protocol marker-base-class handling — applied once, after the shared query/adapter pipeline
/// assembles the structural shape. Mirrors the same "needs a genuine per-language hook" pattern the
/// design doc calls out for JS's textual `.prototype.` heuristic.
struct PythonPostProcessing: Sendable {
    private static let enumBaseNames: Set<String> = ["Enum", "IntEnum", "IntFlag", "Flag", "StrEnum", "ReprEnum"]
    private static let abstractBaseNames: Set<String> = ["ABC", "ABCMeta"]
    private static let markerBaseNames: Set<String> =
        enumBaseNames.union(abstractBaseNames).union(["Protocol", "Generic"])

    func apply(to artifact: CodeArtifact) -> CodeArtifact {
        var copy = artifact
        copy.types = artifact.types.map(processType)
        copy.globalVariables = artifact.globalVariables.map(processMember)
        copy.freestandingFunctions = artifact.freestandingFunctions.map(processMember)
        // A marker base (`Enum`/`ABC`/`Protocol`/`Generic`) is reflected in `kind`/`.abstract`
        // instead, so the phantom inheritance edge to it is dropped project-wide — the name is
        // unambiguous as a target regardless of which type declared it.
        copy.relationships = artifact.relationships.filter {
            !($0.kind == .inheritance && Self.markerBaseNames.contains($0.target))
        }
        return copy
    }

    private func processType(_ type: TypeDeclaration) -> TypeDeclaration {
        var result = type
        result.accessLevel = PythonAccessConvention().accessLevel(forName: type.name)
        result.nestedTypes = type.nestedTypes.map(processType)

        let markerNames = Set(type.inheritedTypes.map(\.name)).intersection(Self.markerBaseNames)
        if markerNames.contains(where: Self.enumBaseNames.contains) {
            result.kind = .enum
        } else if markerNames.contains("Protocol") {
            result.kind = .protocol
        }
        if !markerNames.isEmpty {
            result.inheritedTypes = type.inheritedTypes.filter { !Self.markerBaseNames.contains($0.name) }
        }

        result.members = type.members.map(processMember)
        if result.kind == .enum {
            let (cases, remaining) = splitEnumCases(from: result.members)
            result.enumCases = cases
            result.members = remaining
        } else {
            result.members = deduplicateMembers(result.members)
        }

        let hasAbstractMember = result.members.contains { $0.modifiers.contains(.abstract) }
        if hasAbstractMember || markerNames.contains(where: Self.abstractBaseNames.contains) {
            if !result.modifiers.contains(.abstract) { result.modifiers.append(.abstract) }
        }
        return result
    }

    /// Applies naming-convention access, `self`/`cls`-parameter dropping, `__init__` →
    /// `.initializer`, and decorator-driven kind/modifier adjustments (`@property`/`@staticmethod`/
    /// `@abstractmethod`/`@classmethod`/`@final`). Also used for module-level globals/freestanding
    /// functions (Python's `extractCallable` handled both uniformly): a global's `kind` is already
    /// `.property` (tagged by the query), so the method-only logic below is a no-op for it — only
    /// the access-convention line at the top applies.
    private func processMember(_ member: Member) -> Member {
        var result = member
        result.accessLevel = PythonAccessConvention().accessLevel(forName: member.name)
        guard result.kind == .method else { return result }

        if let first = result.parameters.first, first.internalName == "self" || first.internalName == "cls" {
            result.parameters.removeFirst()
        }
        if member.name == "__init__" {
            result.kind = .initializer
        }
        let decoratorTails = Set(member.annotations.map { $0.components(separatedBy: ".").last ?? $0 })
        if decoratorTails.contains("property") || decoratorTails.contains("cached_property")
            || decoratorTails.contains("setter") || decoratorTails.contains("getter") {
            result.kind = .property
            result.isComputed = true
        }
        if decoratorTails.contains("staticmethod"), !result.modifiers.contains(.static) {
            result.modifiers.append(.static)
        }
        if decoratorTails.contains("abstractmethod"), !result.modifiers.contains(.abstract) {
            result.modifiers.append(.abstract)
        }
        if decoratorTails.contains("final"), !result.modifiers.contains(.final) {
            result.modifiers.append(.final)
        }
        return result
    }

    /// For an `Enum`-kind type: `NAME = value` properties with no type annotation become enum
    /// cases; everything else (methods, annotated fields) stays a member.
    private func splitEnumCases(from members: [Member]) -> (cases: [EnumCase], remaining: [Member]) {
        var cases: [EnumCase] = []
        var remaining: [Member] = []
        for member in members {
            guard member.kind == .property, member.type == nil else {
                remaining.append(member)
                continue
            }
            cases.append(EnumCase(name: member.name, rawValue: member.initialValue?.text, location: member.location))
        }
        return (cases, remaining)
    }

    /// Deduplicates same-named properties: `self.x = …` synthesis produces one entry per assignment
    /// site (once per method it appears in), and a class-body-declared field of the same name should
    /// win over any synthesized one. Keeps the first typed occurrence, else the first occurrence.
    private func deduplicateMembers(_ members: [Member]) -> [Member] {
        var seenPropertyNames: Set<String> = []
        var result: [Member] = []
        for member in members {
            guard member.kind == .property else {
                result.append(member)
                continue
            }
            guard !seenPropertyNames.contains(member.name) else { continue }
            seenPropertyNames.insert(member.name)
            result.append(member)
        }
        return result
    }
}

/// Python's leading-underscore access convention (there are no access keywords): a dunder
/// (`__init__`) is public; `__x` (not a dunder) is private (name-mangled); `_x` is protected; a
/// plain name is public.
struct PythonAccessConvention: Sendable {
    func accessLevel(forName name: String) -> AccessLevel {
        if name.hasPrefix("__") && name.hasSuffix("__") { return .public }
        if name.hasPrefix("__") { return .private }
        if name.hasPrefix("_") { return .protected }
        return .public
    }
}
