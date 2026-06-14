import ArgumentParser

/// Validates the numeric traversal limits shared by the `diagram` and `image` commands.
///
/// Both `--max-depth` (sequence call-graph depth) and `--max-states` (state-diagram cap) must be
/// at least 1 — zero or negative values produce an empty or meaningless diagram — and are capped
/// to keep a stray huge value from triggering a runaway traversal.
enum DiagramLimitBounds {
    static let depthRange = 1...100
    static let statesRange = 1...1000

    static func validate(maxDepth: Int, maxStates: Int) throws {
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
