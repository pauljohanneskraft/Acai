import Foundation

struct GraphvizNotFoundError: Error, LocalizedError, Equatable, Sendable {
    var errorDescription: String? {
        "SVG output needs Graphviz's `dot` command, which wasn't found on PATH. Install it" +
        " (e.g. `brew install graphviz` on macOS, `apt-get install graphviz` on Debian/Ubuntu)," +
        " or use --format dot and pipe the result through `dot -Tsvg` yourself."
    }
}

struct GraphvizRenderError: Error, LocalizedError, Equatable, Sendable {
    let message: String

    var errorDescription: String? {
        "Graphviz failed to render SVG: \(message)"
    }
}

/// Shells out to Graphviz's `dot` binary to turn already-generated DOT text into self-contained,
/// text-based SVG. Graphviz already solves graph layout; this only pipes to it.
struct GraphvizSVGRenderer {
    let executableURL: URL

    init(executableURL: URL) {
        self.executableURL = executableURL
    }

    /// Searches `PATH` for `dot`. Throws `GraphvizNotFoundError` if it isn't installed.
    init(
        searchPaths: [String] = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
    ) throws {
        let fileManager = FileManager.default
        for directory in searchPaths {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("dot")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                self.init(executableURL: candidate)
                return
            }
        }
        throw GraphvizNotFoundError()
    }

    /// Round-trips through temporary files rather than pipes: `dot`'s own `-o` avoids a stdout
    /// pipe entirely, and a file-backed stdin avoids the deadlock where a large graph could fill
    /// the stdin pipe buffer before `dot` starts draining it.
    func renderSVG(fromDOT dot: String) throws -> String {
        let directory = FileManager.default.temporaryDirectory
        let inputURL = directory.appendingPathComponent("acai-graphviz-\(UUID().uuidString).dot")
        let outputURL = directory.appendingPathComponent("acai-graphviz-\(UUID().uuidString).svg")
        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }
        try dot.write(to: inputURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["-Tsvg", inputURL.path, "-o", outputURL.path]
        process.standardOutput = FileHandle.nullDevice

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrMessage = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let stderrMessage, !stderrMessage.isEmpty {
                throw GraphvizRenderError(message: stderrMessage)
            }
            throw GraphvizRenderError(message: "exited with status \(process.terminationStatus)")
        }

        return try String(contentsOf: outputURL, encoding: .utf8)
    }
}
