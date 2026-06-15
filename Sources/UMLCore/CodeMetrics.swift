// Static-analysis metrics derived from an (enriched) `CodeArtifact`:
// concept counts, per-module coupling (Robert Martin's Ca/Ce/I/A) and classic
// OO per-type metrics (DIT, NOC, WMC, fan-in/out).

public struct CodeMetrics: Codable, Equatable, Sendable {
    public var counts: Counts
    public var modules: [ModuleCoupling]
    public var types: [TypeMetric]

    public init(counts: Counts, modules: [ModuleCoupling], types: [TypeMetric]) {
        self.counts = counts
        self.modules = modules
        self.types = types
    }

    /// Concept counts across the whole artifact (types counted incl. nested).
    public struct Counts: Codable, Equatable, Sendable {
        public var totalTypes: Int
        public var byKind: [String: Int]
        public var protocols: Int
        public var globalVariables: Int
        public var freestandingFunctions: Int
        public var methods: Int
        public var properties: Int
        public var relationships: Int
        public var relationshipsByKind: [String: Int]
    }

    /// Robert Martin package metrics, one entry per build module.
    public struct ModuleCoupling: Codable, Equatable, Sendable {
        public var name: String
        public var typeCount: Int
        /// Afferent coupling (Ca): external types that depend on this module.
        public var afferentCoupling: Int
        /// Efferent coupling (Ce): external types this module depends on.
        public var efferentCoupling: Int
        /// Instability `I = Ce / (Ca + Ce)` (0 = stable, 1 = unstable).
        public var instability: Double
        /// Abstractness `A = abstractTypes / totalTypes`.
        public var abstractness: Double
    }

    /// Per-type OO metrics.
    public struct TypeMetric: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        /// Depth of inheritance tree (longest in-codebase inheritance/conformance chain).
        public var depthOfInheritance: Int
        /// Number of children (direct in-codebase subtypes/conformers).
        public var numberOfChildren: Int
        /// Weighted methods per class (method count).
        public var weightedMethods: Int
        public var fanIn: Int
        public var fanOut: Int
    }
}

extension CodeArtifact {

    /// Computes static-analysis metrics. Call on an `enriched()` artifact so
    /// relationship endpoints are resolved to type ids.
    public func computeMetrics() -> CodeMetrics {
        let flat = Self.allTypes(types)
        return CodeMetrics(
            counts: computeCounts(flat: flat),
            modules: computeModuleCoupling(flat: flat),
            types: computeTypeMetrics(flat: flat)
        )
    }

    private func computeCounts(flat: [TypeDeclaration]) -> CodeMetrics.Counts {
        var byKind: [String: Int] = [:]
        var methodCount = 0
        var propertyCount = 0
        for type in flat {
            byKind[type.kind.rawValue, default: 0] += 1
            for member in type.members {
                switch member.kind {
                case .property:
                    propertyCount += 1
                case .method, .initializer, .deinitializer, .subscript:
                    methodCount += 1
                }
            }
        }
        var relByKind: [String: Int] = [:]
        for rel in relationships { relByKind[rel.kind.rawValue, default: 0] += 1 }

        return CodeMetrics.Counts(
            totalTypes: flat.count,
            byKind: byKind,
            protocols: byKind[TypeKind.protocol.rawValue, default: 0],
            globalVariables: globalVariables.count,
            freestandingFunctions: freestandingFunctions.count,
            methods: methodCount,
            properties: propertyCount,
            relationships: relationships.count,
            relationshipsByKind: relByKind
        )
    }

    private func computeTypeMetrics(flat: [TypeDeclaration]) -> [CodeMetrics.TypeMetric] {
        let typeIds = Set(flat.map(\.id))
        let isaEdges = relationships.filter {
            ($0.kind == .inheritance || $0.kind == .conformance)
                && typeIds.contains($0.source) && typeIds.contains($0.target)
        }
        var childCount: [String: Int] = [:]
        var parents: [String: [String]] = [:]
        for edge in isaEdges {
            childCount[edge.target, default: 0] += 1
            parents[edge.source, default: []].append(edge.target)
        }

        var ditMemo: [String: Int] = [:]
        func depth(of id: String, visiting: Set<String>) -> Int {
            if let cached = ditMemo[id] { return cached }
            guard let ps = parents[id] else { ditMemo[id] = 0; return 0 }
            var best = 0
            for parent in ps where !visiting.contains(parent) {
                best = max(best, 1 + depth(of: parent, visiting: visiting.union([id])))
            }
            ditMemo[id] = best
            return best
        }

        let depKinds: Set<Relationship.Kind> = [.dependency, .composition, .aggregation, .association]
        var fanOut: [String: Set<String>] = [:]
        var fanIn: [String: Set<String>] = [:]
        for edge in relationships where depKinds.contains(edge.kind) {
            fanOut[edge.source, default: []].insert(edge.target)
            fanIn[edge.target, default: []].insert(edge.source)
        }

        return flat.map { type in
            CodeMetrics.TypeMetric(
                id: type.id,
                name: type.qualifiedName,
                depthOfInheritance: depth(of: type.id, visiting: [type.id]),
                numberOfChildren: childCount[type.id, default: 0],
                weightedMethods: type.members.filter { $0.kind == .method }.count,
                fanIn: fanIn[type.id]?.count ?? 0,
                fanOut: fanOut[type.id]?.count ?? 0
            )
        }
    }

    private func computeModuleCoupling(flat: [TypeDeclaration]) -> [CodeMetrics.ModuleCoupling] {
        var idToModule: [String: String] = [:]
        var moduleTypes: [String: [TypeDeclaration]] = [:]
        for type in flat {
            let module = BuildProduct.productName(forFilePath: type.location?.filePath ?? "")
            idToModule[type.id] = module
            moduleTypes[module, default: []].append(type)
        }
        var efferent: [String: Set<String>] = [:]
        var afferent: [String: Set<String>] = [:]
        for edge in relationships {
            guard let sourceModule = idToModule[edge.source],
                  let targetModule = idToModule[edge.target],
                  sourceModule != targetModule
            else { continue }
            efferent[sourceModule, default: []].insert(edge.target)
            afferent[targetModule, default: []].insert(edge.source)
        }

        return moduleTypes.keys.sorted().map { name in
            let moduleTypeList = moduleTypes[name] ?? []
            let efferentCount = efferent[name]?.count ?? 0
            let afferentCount = afferent[name]?.count ?? 0
            let total = efferentCount + afferentCount
            // Abstract types per Martin's metric = interfaces/protocols *and* abstract classes.
            // The `.abstract` modifier covers languages (e.g. Dart) whose abstraction idiom is an
            // `abstract class` rather than a dedicated interface/protocol kind.
            let abstractCount = moduleTypeList.filter {
                $0.kind == .protocol || $0.kind == .interface || $0.modifiers.contains(.abstract)
            }.count
            return CodeMetrics.ModuleCoupling(
                name: name,
                typeCount: moduleTypeList.count,
                afferentCoupling: afferentCount,
                efferentCoupling: efferentCount,
                instability: total == 0 ? 0 : Double(efferentCount) / Double(total),
                abstractness: moduleTypeList.isEmpty ? 0 : Double(abstractCount) / Double(moduleTypeList.count)
            )
        }
    }
}
