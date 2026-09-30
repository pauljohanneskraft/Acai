import Foundation

/// Character-level scanner for the TOML subset ``TOMLReader`` accepts. It is strict about structure
/// — quotes, brackets, braces and `=` must balance — and lenient about scalar content, which it
/// captures verbatim rather than validating, so a valid file is never rejected over a number or date
/// shape nothing reads.
struct TOMLScanner {
    enum Statement: Equatable {
        case table([String])
        case arrayTable([String])
        case assignment([String], TOMLValue)
    }

    private let characters: [Character]
    private var index: Int = 0
    private var line: Int = 1
    private var column: Int = 1

    init(_ source: String) {
        characters = Array(source)
    }

    // MARK: - Statements

    mutating func nextStatement() throws -> Statement? {
        skipInsignificant()
        guard let character = peek() else { return nil }
        if character == "[" { return try tableHeader() }
        let key = try keyPath()
        try expect("=")
        let value = try value()
        try endOfLine()
        return .assignment(key, value)
    }

    private mutating func tableHeader() throws -> Statement {
        advance()
        let isArray = peek() == "["
        if isArray { advance() }
        let path = try keyPath()
        try expect("]")
        if isArray { try expect("]") }
        try endOfLine()
        return isArray ? .arrayTable(path) : .table(path)
    }

    private mutating func keyPath() throws -> [String] {
        var parts: [String] = []
        repeat {
            skipSpaces()
            parts.append(try keySegment())
            skipSpaces()
        } while match(".")
        return parts
    }

    private mutating func keySegment() throws -> String {
        guard let character = peek() else { throw failure("expected a key") }
        if character.isTOMLQuote { return try stringLiteral() }
        var segment = ""
        while let next = peek(), next.isTOMLBareKey {
            segment.append(next)
            advance()
        }
        guard !segment.isEmpty else { throw failure("expected a key, found '\(character)'") }
        return segment
    }

    // MARK: - Values

    mutating func value() throws -> TOMLValue {
        skipSpaces()
        guard let character = peek() else { throw failure("expected a value") }
        switch character {
        case "\"", "'": return .string(try stringLiteral())
        case "[": return try array()
        case "{": return try inlineTable()
        default: return .scalar(try scalar())
        }
    }

    private mutating func array() throws -> TOMLValue {
        advance()
        var values: [TOMLValue] = []
        while true {
            skipInsignificant()
            if match("]") { return .array(values) }
            values.append(try value())
            skipInsignificant()
            if match(",") { continue }
            skipInsignificant()
            if match("]") { return .array(values) }
            throw failure("expected ',' or ']' in an array")
        }
    }

    private mutating func inlineTable() throws -> TOMLValue {
        advance()
        var table: [String: TOMLValue] = [:]
        skipInsignificant()
        if match("}") { return .table(table) }
        while true {
            skipInsignificant()
            let key = try keyPath()
            try expect("=")
            let value = try value()
            table.assign(value, at: key)
            skipInsignificant()
            if match(",") { continue }
            if match("}") { return .table(table) }
            throw failure("expected ',' or '}' in an inline table")
        }
    }

    /// Everything up to the value's terminator, kept verbatim — see ``TOMLValue/scalar(_:)``.
    private mutating func scalar() throws -> String {
        var raw = ""
        while let character = peek(), !",]}#\n".contains(character) {
            raw.append(character)
            advance()
        }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw failure("expected a value") }
        return trimmed
    }

    // MARK: - Strings

    private mutating func stringLiteral() throws -> String {
        guard let quote = peek() else { throw failure("expected a string") }
        if matches(String(repeating: quote, count: 3)) {
            return try multilineString(quote: quote)
        }
        advance()
        var contents = ""
        while let character = peek() {
            if character == quote { advance(); return contents }
            if character == "\n" { throw failure("unterminated string") }
            if quote == "\"" && character == "\\" {
                advance()
                contents.append(try escape())
                continue
            }
            contents.append(character)
            advance()
        }
        throw failure("unterminated string")
    }

    private mutating func multilineString(quote: Character) throws -> String {
        let delimiter = String(repeating: quote, count: 3)
        for _ in 0..<3 { advance() }
        if peek() == "\n" { advance() }
        var contents = ""
        while peek() != nil {
            if matches(delimiter) {
                for _ in 0..<3 { advance() }
                return contents
            }
            guard let character = peek() else { break }
            contents.append(character)
            advance()
        }
        throw failure("unterminated multi-line string")
    }

    /// Only the escapes a package-layout value can plausibly carry; `\uXXXX` and friends are left to
    /// the strict-structure rule, since a path containing one is not a shape this reader serves.
    private mutating func escape() throws -> Character {
        guard let character = peek() else { throw failure("unterminated escape sequence") }
        advance()
        switch character {
        case "n": return "\n"
        case "t": return "\t"
        case "r": return "\r"
        case "\"", "'", "\\", "/": return character
        default: throw failure("unsupported escape '\\\(character)'")
        }
    }

    // MARK: - Trivia

    private mutating func skipSpaces() {
        while let character = peek(), character.isTOMLSpace { advance() }
    }

    /// Whitespace, newlines and comments — everything that carries no meaning between tokens.
    mutating func skipInsignificant() {
        while let character = peek() {
            if character.isTOMLWhitespace {
                advance()
            } else if character == "#" {
                skipComment()
            } else {
                return
            }
        }
    }

    private mutating func skipComment() {
        while let character = peek(), character != "\n" { advance() }
    }

    private mutating func endOfLine() throws {
        skipSpaces()
        if peek() == "#" { skipComment() }
        guard let character = peek() else { return }
        guard character.isTOMLNewline else {
            throw failure("unexpected '\(character)' after a value")
        }
        advance()
    }

    // MARK: - Primitives

    private func peek() -> Character? {
        index < characters.count ? characters[index] : nil
    }

    private func matches(_ text: String) -> Bool {
        let expected = Array(text)
        guard index + expected.count <= characters.count else { return false }
        return Array(characters[index..<(index + expected.count)]) == expected
    }

    private mutating func advance() {
        guard index < characters.count else { return }
        if characters[index] == "\n" {
            line += 1
            column = 1
        } else {
            column += 1
        }
        index += 1
    }

    private mutating func match(_ character: Character) -> Bool {
        skipSpaces()
        guard peek() == character else { return false }
        advance()
        return true
    }

    private mutating func expect(_ character: Character) throws {
        guard match(character) else {
            throw failure("expected '\(character)'")
        }
    }

    func failure(_ message: String) -> TOMLParseError {
        TOMLParseError(line: line, column: column, message: message)
    }
}

extension [String: TOMLValue] {
    /// Assigns through a dotted key, creating the intermediate tables it names.
    mutating func assign(_ value: TOMLValue, at path: [String]) {
        guard let head = path.first else { return }
        guard path.count > 1 else {
            self[head] = value
            return
        }
        var child = self[head]?.tableValue ?? [:]
        child.assign(value, at: Array(path.dropFirst()))
        self[head] = .table(child)
    }
}

extension Character {
    var isTOMLQuote: Bool { self == "\"" || self == "'" }
    var isTOMLNewline: Bool { self == "\n" || self == "\r" }
    var isTOMLSpace: Bool { self == " " || self == "\t" }
    var isTOMLWhitespace: Bool { isTOMLSpace || isTOMLNewline }
    var isTOMLBareKey: Bool { isLetter || isNumber || self == "_" || self == "-" }
}
