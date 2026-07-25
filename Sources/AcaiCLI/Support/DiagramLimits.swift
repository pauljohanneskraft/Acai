import ArgumentParser

/// The numeric traversal limits shared by the `diagram` and `image` commands. `--max-depth` and
/// `--max-states` must be at least 1 and are capped to prevent a runaway traversal.
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
