/// How a user-initiated operation ended. A failure has already been reported to the user.
enum OperationOutcome: Equatable {
    case completed
    case cancelled
    case failed
}
