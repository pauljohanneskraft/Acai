import Foundation

/// A CMake listfile's `add_subdirectory()` declarations, read as text.
///
/// CMake listfiles are programs, so this reads only the one command that composes a project from
/// parts: `add_subdirectory(<dir> [<binary_dir>] [EXCLUDE_FROM_ALL])`. Just the first argument names a
/// source directory — `EXCLUDE_FROM_ALL` concerns the default build target rather than whether the
/// code exists, so it is not read. Comments are skipped, so a commented-out call names no
/// sub-directory.
struct CMakeListsFile {

    /// What one `add_subdirectory()` call names.
    enum Subdirectory: Equatable {
        /// A directory named outright, relative to the listfile's own directory or absolute.
        case literal(String)
        /// An argument carrying a variable reference, an environment lookup or a generator expression,
        /// which only CMake itself can expand.
        case computed(argument: String)
    }

    private let characters: [Character]

    init(source: String) {
        characters = Array(source)
    }

    /// The first argument of every `add_subdirectory()` call, in source order.
    var subdirectories: [Subdirectory] {
        var found: [Subdirectory] = []
        var index = 0
        while index < characters.count {
            if let end = commentEnd(at: index) {
                index = end
            } else if let open = callOpening(at: index) {
                let (subdirectory, end) = firstArgument(from: open)
                if let subdirectory { found.append(subdirectory) }
                index = max(end, index + 1)
            } else {
                index += 1
            }
        }
        return found
    }

    /// The index just past the `(` of an `add_subdirectory` call starting at `index` — nil when the
    /// word is part of a longer identifier or opens no call. CMake command names are
    /// case-insensitive, so `ADD_SUBDIRECTORY(` is the same command.
    private func callOpening(at index: Int) -> Int? {
        let word = Array("add_subdirectory")
        guard index + word.count <= characters.count,
              characters[index..<(index + word.count)].elementsEqual(word, by: { $0.lowercasedCharacter == $1 }),
              !(index > 0 && characters[index - 1].isCMakeIdentifier) else { return nil }
        var cursor = index + word.count
        while cursor < characters.count, characters[cursor].isWhitespace { cursor += 1 }
        guard cursor < characters.count, characters[cursor] == "(" else { return nil }
        return cursor + 1
    }

    /// The call's first argument, read from just past its `(`, and the index to resume scanning at.
    /// Nil for `add_subdirectory()`, which names nothing.
    private func firstArgument(from open: Int) -> (Subdirectory?, Int) {
        var cursor = open
        while cursor < characters.count, characters[cursor].isWhitespace { cursor += 1 }
        guard cursor < characters.count, characters[cursor] != ")" else { return (nil, cursor) }
        let (text, end) = argument(at: cursor)
        guard !text.isEmpty else { return (nil, end) }
        // `$` opens every form CMake expands at configure time: `${VAR}`, `$ENV{…}`, `$<…>`.
        return (text.contains("$") ? .computed(argument: text) : .literal(text), end)
    }

    /// The argument starting at `index`, quoted or bare, and the index just past it.
    private func argument(at index: Int) -> (text: String, end: Int) {
        guard characters[index] == "\"" else {
            let end = characters[index...].firstIndex { $0.isWhitespace || $0 == ")" } ?? characters.count
            return (String(characters[index..<end]), end)
        }
        var cursor = index + 1
        var text = ""
        while cursor < characters.count, characters[cursor] != "\"" {
            if characters[cursor] == "\\", cursor + 1 < characters.count { cursor += 1 }
            text.append(characters[cursor])
            cursor += 1
        }
        return (text, min(cursor + 1, characters.count))
    }

    /// The index just past the comment starting at `index` — nil when none starts there. A `#` runs to
    /// the end of the line unless it opens a bracket comment (`#[[ … ]]`, `#[=[ … ]=]`), which runs to
    /// the matching close whatever lines it spans.
    private func commentEnd(at index: Int) -> Int? {
        guard characters[index] == "#" else { return nil }
        guard let equalSigns = bracketOpening(at: index + 1) else {
            return characters[(index + 1)...].firstIndex(of: "\n") ?? characters.count
        }
        let close = Array("]" + String(repeating: "=", count: equalSigns) + "]")
        var cursor = index + 2 + equalSigns
        while cursor + close.count <= characters.count {
            if characters[cursor..<(cursor + close.count)].elementsEqual(close) {
                return cursor + close.count
            }
            cursor += 1
        }
        return characters.count
    }

    /// The number of `=` in a `[`, `=`-run, `[` bracket opening at `index` — nil when none starts there.
    private func bracketOpening(at index: Int) -> Int? {
        guard index < characters.count, characters[index] == "[" else { return nil }
        var cursor = index + 1
        while cursor < characters.count, characters[cursor] == "=" { cursor += 1 }
        guard cursor < characters.count, characters[cursor] == "[" else { return nil }
        return cursor - index - 1
    }
}

private extension Character {

    var isCMakeIdentifier: Bool { isLetter || isNumber || self == "_" }

    /// This character lowercased, left as it is when lowercasing it is not a single character.
    var lowercasedCharacter: Character { lowercased().count == 1 ? Character(lowercased()) : self }
}
