import Foundation

/// Errors surfaced as tool-call error responses in the MCP protocol.
enum MCPToolError: Error, CustomStringConvertible {
    case invalidPath(String)
    case missingArgument(String)
    case analysisError(String)

    var description: String {
        switch self {
        case .invalidPath(let path):
            return "Path does not exist or is not accessible: \(path)"
        case .missingArgument(let name):
            return "Missing required argument: \(name)"
        case .analysisError(let message):
            return message
        }
    }
}
