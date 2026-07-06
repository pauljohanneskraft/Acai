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
        /// Distance from the main sequence `D = |A + I - 1|` (0 = on the sequence, 1 = worst).
        public var distanceFromMainSequence: Double
        /// Public/open members across the module's types — the module's outward API surface.
        public var publicMemberCount: Int
        /// Stable-Dependencies-Principle breaches: modules this one depends on that are *less* stable
        /// than it (higher instability) — a dependency on something likelier to change than you, so an
        /// edit there ripples up into this stabler module. Not a cycle, so cycle detection misses it.
        /// Sorted for stable output; empty when the module only depends on equally- or more-stable ones.
        public var stableDependencyViolations: [String]
    }

    /// Per-type OO metrics.
    public struct TypeMetric: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        /// The build module the type is declared in (resolved from its file path) — lets per-type
        /// metrics be grouped or disambiguated by module (type ids are not module-qualified).
        public var module: String
        /// Depth of inheritance tree (longest in-codebase inheritance/conformance chain).
        public var depthOfInheritance: Int
        /// Number of children (direct in-codebase subtypes/conformers).
        public var numberOfChildren: Int
        /// Weighted methods per class (method count).
        public var weightedMethods: Int
        /// Stored/computed property count — the data half of the anemic-vs-behaviour balance.
        public var numberOfProperties: Int
        public var fanIn: Int
        public var fanOut: Int
        /// Response For a Class: declared methods + distinct call targets in member bodies (see
        /// ``ResponseForClass``). High RFC = a large response set, costly to test and reason about.
        public var responseForClass: Int
        /// Public/open members — the type's outward API surface.
        public var publicMemberCount: Int
        /// Fraction of members that are public/open (0 when the type has no members).
        public var publicMemberRatio: Double
        /// Publicly settable stored properties — mutable public state that breaks encapsulation.
        public var mutablePublicState: Int
        /// Largest parameter count of any callable member — the long-parameter-list smell.
        public var maxParameters: Int
        /// Mean parameter count across the type's callable members.
        public var meanParameters: Double
        /// Data-class / anemic score: `properties / (properties + methods)` (1 = pure data).
        public var dataClassScore: Double
        /// Members that `override` an inherited member — refused-bequest candidates.
        public var overrideCount: Int
        /// Depth of the nested-type tree rooted at this type (0 when it declares no nested types).
        public var nestingDepth: Int
        /// LCOM4-style lack of cohesion: connected components among the type's methods (1 = cohesive;
        /// higher = several unrelated responsibilities). See ``LcomAnalysis``.
        public var lackOfCohesion: Int
        /// Methods more interested in another declared type than their own — feature envy. See
        /// ``FeatureEnvy``.
        public var featureEnvyMethods: Int

        /// Deep-and-wide inheritance shape (`DIT × NOC`): a type that is both deeply derived and widely
        /// subclassed sits at a fragile hierarchy hub. Stored (not computed) so it serializes alongside
        /// every other metric — filled from `depthOfInheritance × numberOfChildren` in `computeTypeMetrics`.
        public var deepAndWide: Int
    }
}

extension CodeArtifact {

    /// Computes static-analysis metrics. Call on an `enriched()` artifact so
    /// relationship endpoints are resolved to type ids.
    public func computeMetrics() -> CodeMetrics {
        let flat = Self.allTypes(types)
        // Resolves a body-referenced type name to its canonical id (only known types resolve), shared
        // by the coupling and per-type fan metrics so construction/body dependencies are counted.
        let identity = TypeIdentityResolver(types: types)
        return CodeMetrics(
            counts: computeCounts(flat: flat),
            modules: computeModuleCoupling(flat: flat, identity: identity),
            types: computeTypeMetrics(flat: flat, identity: identity)
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

    private func computeTypeMetrics(
        flat: [TypeDeclaration], identity: TypeIdentityResolver
    ) -> [CodeMetrics.TypeMetric] {
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

        let (fanIn, fanOut) = fanMetrics(flat: flat, identity: identity)
        // Nesting depth reads a type's `nestedTypes`, which `allTypes(_:)` clears on the flattened
        // copies — so measure it over the original (un-flattened) tree, keyed by id.
        let nesting = nestingDepths(types)

        let resolver = ModuleResolver.standard
        // `depth(of:)` is memoised, so reading it twice (DIT and the derived deep-and-wide) is cheap.
        return flat.map { type in
            CodeMetrics.TypeMetric(
                id: type.id,
                name: type.qualifiedName,
                module: resolver.productName(forFilePath: type.location?.filePath ?? ""),
                depthOfInheritance: depth(of: type.id, visiting: [type.id]),
                numberOfChildren: childCount[type.id, default: 0],
                weightedMethods: type.members.filter { $0.kind == .method }.count,
                numberOfProperties: type.members.filter { $0.kind == .property }.count,
                fanIn: fanIn[type.id]?.count ?? 0,
                fanOut: fanOut[type.id]?.count ?? 0,
                responseForClass: ResponseForClass(type: type).count,
                publicMemberCount: type.publicMemberCount,
                publicMemberRatio: type.publicMemberRatio,
                mutablePublicState: type.mutablePublicState,
                maxParameters: type.maxParameters,
                meanParameters: type.meanParameters,
                dataClassScore: type.dataClassScore,
                overrideCount: type.overrideCount,
                nestingDepth: nesting[type.id] ?? 0,
                lackOfCohesion: LcomAnalysis(type: type).componentCount,
                featureEnvyMethods: FeatureEnvy(type: type, identity: identity).enviousMethodCount,
                deepAndWide: depth(of: type.id, visiting: [type.id]) * childCount[type.id, default: 0]
            )
        }
    }

    /// Subtree nesting depth per type id, walked over the original (un-flattened) `types` tree where
    /// `nestedTypes` is still populated (``CodeArtifact/allTypes(_:)`` clears it on flattened copies).
    private func nestingDepths(_ roots: [TypeDeclaration]) -> [String: Int] {
        var result: [String: Int] = [:]
        for type in roots {
            result[type.id] = type.nestingDepth
            result.merge(nestingDepths(type.nestedTypes)) { current, _ in current }
        }
        return result
    }

    /// Per-type fan-in/fan-out sets: signature edges (dependency/composition/aggregation/association)
    /// plus construction/body dependencies (a member referencing a known type couples its owning type
    /// to that type — not visible in signatures, e.g. a factory that constructs the type).
    private func fanMetrics(
        flat: [TypeDeclaration], identity: TypeIdentityResolver
    ) -> (fanIn: [String: Set<String>], fanOut: [String: Set<String>]) {
        let depKinds: Set<Relationship.Kind> = [.dependency, .composition, .aggregation, .association]
        var fanOut: [String: Set<String>] = [:]
        var fanIn: [String: Set<String>] = [:]
        for edge in relationships where depKinds.contains(edge.kind) {
            fanOut[edge.source, default: []].insert(edge.target)
            fanIn[edge.target, default: []].insert(edge.source)
        }
        for type in flat {
            for member in type.members {
                for name in member.referencedTypeNames {
                    guard let target = identity.resolvedID(for: name)?.value, target != type.id else { continue }
                    fanOut[type.id, default: []].insert(target)
                    fanIn[target, default: []].insert(type.id)
                }
            }
        }
        return (fanIn, fanOut)
    }

    private func computeModuleCoupling(
        flat: [TypeDeclaration], identity: TypeIdentityResolver
    ) -> [CodeMetrics.ModuleCoupling] {
        let resolver = ModuleResolver.standard
        var idToModule: [String: String] = [:]
        var moduleTypes: [String: [TypeDeclaration]] = [:]
        for type in flat {
            let module = resolver.productName(forFilePath: type.location?.filePath ?? "")
            idToModule[type.id] = module
            moduleTypes[module, default: []].append(type)
        }
        // Attribute each edge's source to where it was *declared* (honouring `origin` provenance),
        // so a cross-module extension counts toward the extension's module, not the extended type's.
        let attribution = ModuleAttribution(resolver: resolver, idToModule: idToModule)
        var sets = ModuleCouplingSets()
        for edge in relationships {
            guard let sourceModule = attribution.sourceModule(of: edge),
                  let targetModule = attribution.targetModule(of: edge),
                  sourceModule != targetModule
            else { continue }
            sets.record(sourceModule: sourceModule, targetModule: targetModule,
                        edgeTarget: edge.target, edgeSource: edge.source)
        }
        addBodyReferenceCoupling(flat: flat, identity: identity, idToModule: idToModule, into: &sets)

        return moduleCouplings(moduleTypes: moduleTypes, sets: sets)
    }

    /// Construction/body dependencies between modules. The source module is the *member's* declaring
    /// file (so an extension on a foreign type counts toward the extension's module, not the type's),
    /// the target is the referenced type's module. Mutates the shared efferent/afferent sets.
    private func addBodyReferenceCoupling(
        flat: [TypeDeclaration], identity: TypeIdentityResolver, idToModule: [String: String],
        into sets: inout ModuleCouplingSets
    ) {
        let resolver = ModuleResolver.standard
        for type in flat {
            for member in type.members {
                let sourceModule = resolver.productName(
                    forFilePath: member.location?.filePath ?? type.location?.filePath ?? "")
                for name in member.referencedTypeNames {
                    guard let target = identity.resolvedID(for: name)?.value, let targetModule = idToModule[target],
                          sourceModule != targetModule
                    else { continue }
                    sets.record(sourceModule: sourceModule, targetModule: targetModule,
                                edgeTarget: target, edgeSource: type.id)
                }
            }
        }
    }

    /// Assembles a `ModuleCoupling` per module from the resolved coupling sets.
    private func moduleCouplings(
        moduleTypes: [String: [TypeDeclaration]], sets: ModuleCouplingSets
    ) -> [CodeMetrics.ModuleCoupling] {
        let efferent = sets.efferent
        let afferent = sets.afferent
        let moduleAdjacency = sets.moduleAdjacency
        func instability(of module: String) -> Double {
            let total = (efferent[module]?.count ?? 0) + (afferent[module]?.count ?? 0)
            return total == 0 ? 0 : Double(efferent[module]?.count ?? 0) / Double(total)
        }
        return moduleTypes.keys.sorted().map { name in
            let moduleTypeList = moduleTypes[name] ?? []
            let efferentCount = efferent[name]?.count ?? 0
            let afferentCount = afferent[name]?.count ?? 0
            // Abstract types per Martin's metric = interfaces/protocols *and* abstract classes.
            // The `.abstract` modifier covers languages (e.g. Dart) whose abstraction idiom is an
            // `abstract class` rather than a dedicated interface/protocol kind.
            let abstractCount = moduleTypeList.filter {
                $0.kind == .protocol || $0.kind == .interface || $0.modifiers.contains(.abstract)
            }.count
            let instabilityValue = instability(of: name)
            let abstractness = moduleTypeList.isEmpty ? 0 : Double(abstractCount) / Double(moduleTypeList.count)
            // SDP breach: a dependency on a *less*-stable module (strictly higher instability).
            let violations = (moduleAdjacency[name] ?? []).filter { instability(of: $0) > instabilityValue }.sorted()
            return CodeMetrics.ModuleCoupling(
                name: name,
                typeCount: moduleTypeList.count,
                afferentCoupling: afferentCount,
                efferentCoupling: efferentCount,
                instability: instabilityValue,
                abstractness: abstractness,
                distanceFromMainSequence: abs(abstractness + instabilityValue - 1),
                publicMemberCount: moduleTypeList.reduce(0) { $0 + $1.publicMemberCount },
                stableDependencyViolations: violations
            )
        }
    }
}

/// The mutable coupling sets accumulated while walking the artifact's edges: per-module efferent and
/// afferent type ids (Martin's Ce/Ca) plus the module→modules adjacency the Stable-Dependencies check
/// reads. A value that records edges onto itself, keeping the metric walk's parameter lists small.
private struct ModuleCouplingSets {
    var efferent: [String: Set<String>] = [:]
    var afferent: [String: Set<String>] = [:]
    var moduleAdjacency: [String: Set<String>] = [:]

    /// Records one cross-module edge: `edgeTarget`/`edgeSource` are the type ids, `sourceModule`/
    /// `targetModule` their modules (already known to differ).
    mutating func record(sourceModule: String, targetModule: String, edgeTarget: String, edgeSource: String) {
        efferent[sourceModule, default: []].insert(edgeTarget)
        afferent[targetModule, default: []].insert(edgeSource)
        moduleAdjacency[sourceModule, default: []].insert(targetModule)
    }
}
