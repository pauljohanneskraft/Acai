import Foundation

/// An invalid diagram request: a malformed scope/entry-point string, or an input from which nothing
/// could be drawn. Lives in the diagram layer so both entry points (the CLI, the MCP server) raise the
/// same error from the shared request/exporter types; each maps it onto its own surface (the CLI wraps
/// it in an ArgumentParser `ValidationError`, the MCP in an `invalidParams`).
public struct DiagramRequestError: Error, LocalizedError, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}
