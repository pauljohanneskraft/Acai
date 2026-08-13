import Foundation

struct MCPBinaryLocator {
    let fileManager: FileManager
    let candidateDirectories: [String]

    init(
        fileManager: FileManager = .default,
        candidateDirectories: [String] = ["/usr/local/bin", "/opt/homebrew/bin"]
    ) {
        self.fileManager = fileManager
        self.candidateDirectories = candidateDirectories
    }

    var installedBinaryPath: String? {
        candidateDirectories
            .map { "\($0)/\(binaryName)" }
            .first { fileManager.isExecutableFile(atPath: $0) }
    }

    private var binaryName: String { "acai-mcp" }
}
