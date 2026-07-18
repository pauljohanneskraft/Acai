// `Process` doesn't exist in the iOS SDK, so this — and everything built on it (git delta
// comparison) — is macOS-only. See `ProjectBrowserViewModel`'s delta-comparison block and
// `DeltaComparisonBar`, which skip the feature entirely on iOS.
#if os(macOS)
import Foundation

/// Runs a single read-only git subcommand in a working directory and captures its stdout. Shared
/// plumbing behind `GitRevisionSnapshot` (diagram delta snapshots) and `GitRefs` (the git-ref
/// picker) so both stay small collaborators instead of duplicating `Process` bookkeeping.
struct GitCommand {
    let directory: URL
    let arguments: [String]

    enum Failure: LocalizedError {
        case failed(command: String, message: String)

        var errorDescription: String? {
            switch self {
            case .failed(let command, let message):
                "git \(command) failed: \(message)"
            }
        }
    }

    @discardableResult
    func run() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = "exit \(process.terminationStatus)"
            throw Failure.failed(command: arguments.first ?? "git", message: message ?? fallback)
        }
        return String(data: outData, encoding: .utf8) ?? ""
    }
}
#endif
