import ArgumentParser

/// The numeric traversal limits shared by the `diagram` and `image` commands.
///
/// Both `--max-depth` (sequence call-graph depth) and `--max-states` (state-diagram cap) must be at
/// least 1 — zero or negative values produce an empty or meaningless diagram — and are capped to keep
/// a stray huge value from triggering a runaway traversal. A value you instantiate and ask to
/// `validate(maxDepth:maxStates:)`.
struct DiagramLimits {
    var depthRange = 1...100
    var statesRange = 1...1000

    func validate(maxDepth: Int, maxStates: Int) throws {
        guard depthRange.contains(maxDepth) else {
            throw ValidationError(
                "--max-depth must be between \(depthRange.lowerBound) and \(depthRange.upperBound)."
            )
        }
        guard statesRange.contains(maxStates) else {
            throw ValidationError(
                "--max-states must be between \(statesRange.lowerBound) and \(statesRange.upperBound)."
            )
        }
    }
}
