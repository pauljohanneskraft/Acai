import Foundation

/// A static **call graph**: one node per method, a directed edge for every statically
/// resolvable call between them. Built from `Member.callSites`, scoped to a single type or
/// build module so the graph stays legible on large codebases.
///
/// Because call-site extraction is best-effort (dynamic dispatch, closures and
/// generically-typed receivers may not carry a concrete type), the graph also reports its
/// `coverage` — the share of observed call sites it could resolve to a known method — so a
/// consumer can show how complete the picture is.
public struct CallGraph: Codable, Hashable, Sendable {

    // MARK: - Node

    public struct Node: Codable, Hashable, Sendable, Identifiable {
        /// Stable id, as ``CallGraphNodeIdentity`` spells it: the owning type (or, for a free
        /// function, the declaring file) then the member name and its parameter list, so overloads
        /// and same-named file-local functions are separate nodes.
        public var id: String
        /// The owning type's simple name, or its qualified id when another declared type shares that
        /// simple name; empty for a free function.
        public var typeName: String
        public var methodName: String
        /// `true` when the method belongs to the scoped focus (vs. an out-of-scope callee
        /// pulled in as a leaf), so the app can de-emphasise external leaves.
        public var inScope: Bool
        /// The parameter list that distinguishes this node from its same-named overloads, as
        /// ``Member/callGraphParameterList`` renders it. `nil` for a member that declares none.
        public var signature: String?
        /// What qualifies a free function in place of a type: the name of the file declaring it,
        /// which is also what scopes its id. `nil` for a member of a type, and for a free function
        /// whose parser recorded no location.
        public var container: String?

        public init(
            id: String,
            typeName: String,
            methodName: String,
            inScope: Bool,
            signature: String? = nil,
            container: String? = nil
        ) {
            self.id = id
            self.typeName = typeName
            self.methodName = methodName
            self.inScope = inScope
            self.signature = signature
            self.container = container
        }

        public var label: String {
            let qualifier = typeName.isEmpty ? (container ?? "") : typeName
            let qualified = qualifier.isEmpty ? methodName : "\(qualifier).\(methodName)"
            return qualified + (signature ?? "")
        }

        public var isFreeFunction: Bool { typeName.isEmpty }
    }

    // MARK: - Edge

    public struct Edge: Codable, Hashable, Sendable {
        public var from: String
        public var to: String
        /// Number of distinct call sites from `from` to `to`.
        public var weight: Int

        public init(from: String, to: String, weight: Int = 1) {
            self.from = from
            self.to = to
            self.weight = weight
        }
    }

    // MARK: - Coverage

    /// How much of the observed call traffic the graph could resolve.
    public struct Coverage: Codable, Hashable, Sendable {
        /// Call sites whose target method was found in the artifact.
        public var resolved: Int
        /// All call sites observed on in-scope methods.
        public var total: Int

        public init(resolved: Int, total: Int) {
            self.resolved = resolved
            self.total = total
        }

        /// `1` when there were no call sites to resolve, so an empty graph reads as fully covered.
        public var fraction: Double { total == 0 ? 1 : Double(resolved) / Double(total) }
    }

    // MARK: - Diagram

    public var title: String?
    public var nodes: [Node]
    public var edges: [Edge]
    public var coverage: Coverage

    public init(
        title: String? = nil,
        nodes: [Node] = [],
        edges: [Edge] = [],
        coverage: Coverage = Coverage(resolved: 0, total: 0)
    ) {
        self.title = title
        self.nodes = nodes
        self.edges = edges
        self.coverage = coverage
    }
}

/// What the call graph is focused on. The scope bounds which methods are treated as
/// *callers*; resolved callees outside the scope are still drawn as leaf nodes.
public enum CallGraphScope: Codable, Hashable, Sendable {
    case wholeCodebase
    case type(String)
    /// Methods of types in this build module, per `ModuleResolver`.
    case module(String)
}
