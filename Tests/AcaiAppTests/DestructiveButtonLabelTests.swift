import Foundation
import Testing
@testable import AcaiApp

/// A delete button that renders a bare glyph names neither what it deletes nor that it deletes —
/// the consistency bar allows icon-only buttons on a canvas-viewport toolbar, and a destructive
/// action is never one of those. The buttons this covers live in forms, which the render-snapshot
/// layer cannot resolve, so the check reads the source instead of a rendered view.
@Suite("Destructive button labels", .timeLimit(.minutes(1)))
struct DestructiveButtonLabelTests {

    private static let declaration = "Button(role: .destructive)"

    /// A `Button` declaration spans at most this many lines; past that the scan has lost the brace
    /// it was matching and would read the rest of the file as one button.
    private static let maximumDeclarationLines = 40

    private let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/AcaiApp")

    @Test("Every destructive button states its action, not just an icon")
    func destructiveButtonsCarryATitle() throws {
        for file in swiftFiles() {
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

    /// The source of the button starting on `offset`, up to the line closing its last closure. The
    /// `} label: {` form reopens on the same line it closes, so the depth is read per line rather
    /// than per brace.
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
