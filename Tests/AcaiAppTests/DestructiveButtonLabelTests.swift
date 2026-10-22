import Foundation
import Testing
@testable import AcaiApp

/// Reads source rather than a rendered view: these buttons live in forms the render snapshots cannot resolve.
@Suite("Destructive button labels", .timeLimit(.minutes(1)))
struct DestructiveButtonLabelTests {

    private static let declaration = "Button(role: .destructive)"

    private static let maximumDeclarationLines = 40

    private let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/AcaiApp")

    @Test("Every destructive button states its action, not just an icon")
    func destructiveButtonsCarryATitle() throws {
        let files = swiftFiles()
        #expect(!files.isEmpty, "found no sources under \(sourceRoot.path)")
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (offset, line) in lines.enumerated()
            where line.trimmingCharacters(in: .whitespaces).hasPrefix(Self.declaration) {
                let source = button(in: lines, from: offset)
                #expect(
                    source.contains("Label(") || source.contains("Text("),
                    """
                    \(file.lastPathComponent):\(offset + 1): this destructive button renders only \
                    an icon — give it Label(.app("…"), systemImage:) so a reader and VoiceOver both \
                    get the action
                    """
                )
            }
        }
    }

    /// Depth is read per line, since `} label: {` closes and reopens on the same line.
    private func button(in lines: [String], from offset: Int) -> String {
        var depth = 0
        var opened = false
        var collected: [String] = []
        for line in lines[offset..<min(offset + Self.maximumDeclarationLines, lines.count)] {
            collected.append(line)
            if line.contains("{") { opened = true }
            depth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
            if opened, depth <= 0 { break }
        }
        return collected.joined(separator: "\n")
    }

    private func swiftFiles() -> [URL] {
        guard let walker = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil) else {
            return []
        }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
