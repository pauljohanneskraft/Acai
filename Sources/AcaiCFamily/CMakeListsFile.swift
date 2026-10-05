import Foundation

/// A CMake listfile's `add_subdirectory()` declarations, read as text past comments and quoted arguments.
struct CMakeListsFile {

    struct Declaration: Equatable {
        let directory: Subdirectory
        let line: Int
    }

    enum Subdirectory: Equatable {
        case literal(String)
        /// A variable, environment lookup or generator expression only CMake can expand.
        case computed(argument: String)
    }

    private let characters: [Character]

    init(source: String) {
        characters = Array(source)
    }

    var subdirectories: [Declaration] {
        var found: [Declaration] = []
        var index = 0
        while index < characters.count {
            if let end = commentEnd(at: index) ?? stringLiteralEnd(at: index) {
                index = end
            } else if let open = callOpening(at: index) {
                let (subdirectory, end) = firstArgument(from: open)
                if let subdirectory { found.append(Declaration(directory: subdirectory, line: line(at: index))) }
                index = max(end, index + 1)
            } else {
                index += 1
            }
        }
        return found
    }

    private func line(at index: Int) -> Int {
        characters[..<index].reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }

    /// The index just past the `(`; command names are case-insensitive.
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

    private func firstArgument(from open: Int) -> (Subdirectory?, Int) {
        var cursor = open
        while cursor < characters.count {
            if characters[cursor].isWhitespace {
                cursor += 1
            } else if let end = commentEnd(at: cursor) {
                cursor = end
            } else {
                break
            }
        }
        guard cursor < characters.count, characters[cursor] != ")" else { return (nil, cursor) }
        let (text, end) = argument(at: cursor)
        guard !text.isEmpty else { return (nil, end) }
        // `$` opens every form CMake expands at configure time: `${VAR}`, `$ENV{…}`, `$<…>`.
        return (text.contains("$") ? .computed(argument: text) : .literal(text), end)
    }

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

    /// Nil for an unclosed quote, which is then read as ordinary text.
    private func stringLiteralEnd(at index: Int) -> Int? {
        guard characters[index] == "\"" else { return nil }
        var cursor = index + 1
        while cursor < characters.count {
            if characters[cursor] == "\\" {
                cursor += 2
                continue
            }
            if characters[cursor] == "\"" { return cursor + 1 }
            cursor += 1
        }
        return nil
    }

    /// A line comment, or a bracket comment (`#[[ … ]]`, `#[=[ … ]=]`) spanning any number of lines.
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

    /// The number of `=` in a `[=…=[` opening at `index`.
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

    var lowercasedCharacter: Character { lowercased().count == 1 ? Character(lowercased()) : self }
}
