/// How a user-initiated operation ended. A failure has already been reported to the user.
public enum OperationOutcome: Equatable, Sendable {
    case completed
    case cancelled
    case failed
}
