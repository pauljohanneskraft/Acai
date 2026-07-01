/// Per-module coupling-metric movement. Only the metrics that actually changed are populated.
public struct ModuleMetricDelta: Codable, Equatable, Sendable {
    public var module: String
    public var instability: Change<Double>?
    public var abstractness: Change<Double>?
    public var distanceFromMainSequence: Change<Double>?

    public init(
        module: String,
        instability: Change<Double>? = nil,
        abstractness: Change<Double>? = nil,
        distanceFromMainSequence: Change<Double>? = nil
    ) {
        self.module = module
        self.instability = instability
        self.abstractness = abstractness
        self.distanceFromMainSequence = distanceFromMainSequence
    }
}

/// Per-type OO-metric movement. Only the metrics that actually changed are populated.
public struct TypeMetricDelta: Codable, Equatable, Sendable {
    public var id: String
    public var fanIn: Change<Int>?
    public var fanOut: Change<Int>?
    public var depthOfInheritance: Change<Int>?

    public init(
        id: String,
        fanIn: Change<Int>? = nil,
        fanOut: Change<Int>? = nil,
        depthOfInheritance: Change<Int>? = nil
    ) {
        self.id = id
        self.fanIn = fanIn
        self.fanOut = fanOut
        self.depthOfInheritance = depthOfInheritance
    }
}
