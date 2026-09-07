// swiftlint:disable:next unused_import - required on macOS; the Linux analyzer disagrees
import Foundation

struct ValidationError: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
