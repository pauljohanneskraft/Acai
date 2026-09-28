/// The seeds every property-based invariant runs over, so the suites all cover the same artifacts and
/// a failure in one is reproducible in the others. Fixed rather than random per run: a property test
/// that samples a different corpus on every run turns a real defect into an intermittent failure.
public struct ArtifactInvariantSeeds: Sendable {
    public static let standard = ArtifactInvariantSeeds(count: 200)

    public let seeds: [UInt64]

    public init(count: Int, from first: UInt64 = 1) {
        seeds = (0..<UInt64(count)).map { first &+ $0 }
    }
}
