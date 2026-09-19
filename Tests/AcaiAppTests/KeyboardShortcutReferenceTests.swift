import Foundation
import Testing
@testable import AcaiApp

@Suite("Keyboard Shortcut Reference")
struct KeyboardShortcutReferenceTests {
    private let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/AcaiApp")

    private var allShortcuts: [KeyboardShortcutReference] {
        KeyboardShortcutReference.allGroups.flatMap(\.shortcuts)
    }

    @Test("Every group has a non-empty title and at least one shortcut")
    func groupsAreWellFormed() {
        for group in KeyboardShortcutReference.allGroups {
            #expect(!String(localized: group.title).isEmpty)
            #expect(!group.shortcuts.isEmpty)
        }
    }

    @Test("Every shortcut has a non-empty name and an id unique across the reference")
    func shortcutsAreWellFormed() {
        for shortcut in allShortcuts {
            #expect(!String(localized: shortcut.name).isEmpty)
        }
        let ids = allShortcuts.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Symbols are derived from the bound key and modifiers")
    func symbolsMatchBinding() {
        #expect(KeyboardShortcutReference.fitToView.symbol == "⌘0")
        #expect(KeyboardShortcutReference.previousMatch.symbol == "⇧⌘G")
        #expect(KeyboardShortcutReference.deleteSelection.symbol == "⌫")
        #expect(KeyboardShortcutReference.cancelDialog.symbol == "⎋")
        #expect(KeyboardShortcutReference.confirmDialog.symbol == "↩")
        #expect(KeyboardShortcutReference.keyboardShortcuts.symbol == "⇧⌘/")
        #expect(KeyboardShortcutReference.quickOpen.symbol == "⌘K")
    }

    /// An iPad's hardware keyboard fires the same menu commands the Mac's menu bar does, so a command that
    /// binds a shortcut but is attached only on macOS silently drops that shortcut on iPad.
    @Test("No shortcut-binding menu command is attached on macOS only")
    func shortcutCommandsAreAttachedOnEveryPlatform() throws {
        let sources = try swiftFiles().map { try String(contentsOf: $0, encoding: .utf8) }
        let commandTypes = sources
            .filter { $0.contains(".keyboardShortcut(") }
            .flatMap { $0.matches(of: /struct (\w+)\s*:\s*Commands/).map { String($0.1) } }
        #expect(!commandTypes.isEmpty)
        for type in commandTypes {
            let attachments = sources.flatMap { MacOSOnlyRegions(source: $0).lines(containing: "\(type)()") }
            #expect(!attachments.isEmpty, "`\(type)` binds a shortcut but is never attached")
            #expect(
                attachments.allSatisfy { !$0.isMacOSOnly },
                "`\(type)` binds a shortcut but is attached inside `#if os(macOS)`, so an iPad keyboard never fires it")
        }
    }

    @Test("Every shortcut the app binds is listed in the reference")
    func everyBoundShortcutIsListed() throws {
        let listed = Set(allShortcuts.map(\.id))
        let usages = try shortcutUsages()
        #expect(!usages.isEmpty)
        for usage in usages {
            #expect(
                listed.contains(usage.argument),
                """
                \(usage.file): `.keyboardShortcut(\(usage.argument))` must bind a `KeyboardShortcutReference` \
                entry listed in `allGroups`, written as `.keyboardShortcut(.entryName)`
                """)
        }
    }

    @Test("Every listed shortcut is bound somewhere")
    func everyListedShortcutIsBound() throws {
        let bound = Set(try shortcutUsages().map(\.argument))
        for shortcut in allShortcuts {
            #expect(bound.contains(shortcut.id), "`\(shortcut.id)` is listed but never bound")
        }
    }

    @Test("No key is handled outside the reference")
    func noKeyHandlingBypassesTheReference() throws {
        let bypasses = [".onKeyPress(", "UIKeyCommand", "keyCommands", "onExitCommand", "onDeleteCommand"]
        for file in try swiftFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            for marker in bypasses {
                #expect(!source.contains(marker), "\(file.lastPathComponent): \(marker) bypasses the reference")
            }
        }
    }

    private func swiftFiles() throws -> [URL] {
        guard let walker = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil) else {
            return []
        }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    private struct Usage {
        let file: String
        let argument: String
    }

    /// Tracks `#if`/`#else`/`#endif` line by line; a line is macOS-only when any enclosing branch is
    /// `os(macOS)`, or the `#else` of `!os(macOS)`.
    private struct MacOSOnlyRegions {
        struct Line {
            let text: String
            let isMacOSOnly: Bool
        }

        let source: String

        func lines(containing needle: String) -> [Line] {
            var branches: [(condition: String, isElse: Bool)] = []
            var result: [Line] = []
            for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("#if ") {
                    branches.append((String(line.dropFirst(4)), false))
                } else if line.hasPrefix("#elseif "), !branches.isEmpty {
                    branches[branches.count - 1] = (String(line.dropFirst(8)), false)
                } else if line == "#else", !branches.isEmpty {
                    branches[branches.count - 1].isElse = true
                } else if line == "#endif", !branches.isEmpty {
                    branches.removeLast()
                } else if line.contains(needle) {
                    let isMacOSOnly = branches.contains { branch in
                        branch.isElse ? branch.condition == "!os(macOS)" : branch.condition == "os(macOS)"
                    }
                    result.append(Line(text: line, isMacOSOnly: isMacOSOnly))
                }
            }
            return result
        }
    }

    /// The argument of every `.keyboardShortcut(…)` call, reduced to the bare entry name when it is
    /// written `.entryName`, and kept verbatim otherwise so the listing check rejects it.
    private func shortcutUsages() throws -> [Usage] {
        let marker = ".keyboardShortcut("
        var usages: [Usage] = []
        for file in try swiftFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            var searchStart = source.startIndex
            while let range = source.range(of: marker, range: searchStart..<source.endIndex) {
                guard let close = source[range.upperBound...].firstIndex(of: ")") else { break }
                let argument = source[range.upperBound..<close].trimmingCharacters(in: .whitespacesAndNewlines)
                let isEntryName = argument.hasPrefix(".")
                    && argument.dropFirst().allSatisfy { $0.isLetter || $0.isNumber }
                usages.append(Usage(
                    file: file.lastPathComponent,
                    argument: isEntryName ? String(argument.dropFirst()) : argument))
                searchStart = close
            }
        }
        return usages
    }
}
