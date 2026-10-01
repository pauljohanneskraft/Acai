import Foundation

/// Scanner for the TOML subset ``TOMLReader`` accepts. It is strict about structure — quotes,
/// brackets, braces and `=` must balance — and lenient about scalar content, which it captures
/// verbatim rather than validating, so a valid file is never rejected over a number or date shape
/// nothing reads. It works on unicode scalars rather than `Character`s, because a grapheme cluster
/// fuses `\r\n`, or a combining mark with the quote before it, into one unit no token matches.
struct TOMLScanner {
    enum Statement: Equatable {
        case table([String])
        case arrayTable([String])
        case assignment([String], TOMLValue)
    }

    private let scalars: [Unicode.Scalar]
    private var index: Int = 0
    private var line: Int = 1
    private var column: Int = 1

    init(_ source: String) {
        scalars = Array(source.unicodeScalars)
    }

    // MARK: - Statements

    mutating func nextStatement() throws -> Statement? {
        skipInsignificant()
        guard let scalar = peek() else { return nil }
        if scalar == "[" { return try tableHeader() }
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
        guard let scalar = peek() else { throw failure("expected a key") }
        if scalar.isTOMLQuote { return try stringLiteral() }
        var segment = String.UnicodeScalarView()
        while let next = peek(), next.isTOMLBareKey {
            segment.append(next)
            advance()
        }
        guard !segment.isEmpty else { throw failure("expected a key, found '\(scalar.tomlDescription)'") }
        return String(segment)
    }

    // MARK: - Values

    mutating func value() throws -> TOMLValue {
        skipSpaces()
        guard let scalar = peek() else { throw failure("expected a value") }
        switch scalar {
        case "\"", "'":
            return .string(try stringLiteral())
        case "[":
            return try array()
        case "{":
            return try inlineTable()
        default:
            return .scalar(try scalarValue())
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
    private mutating func scalarValue() throws -> String {
        var raw = String.UnicodeScalarView()
        while let scalar = peek(), !scalar.isTOMLNewline, !",]}#".unicodeScalars.contains(scalar) {
            raw.append(scalar)
            advance()
        }
        let trimmed = String(raw).trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw failure("expected a value") }
        return trimmed
    }

    // MARK: - Strings

    private mutating func stringLiteral() throws -> String {
        guard let quote = peek() else { throw failure("expected a string") }
        if matches([quote, quote, quote]) {
            return try multilineString(quote: quote)
        }
        advance()
        var contents = String.UnicodeScalarView()
        while let scalar = peek() {
            if scalar == quote { advance(); return String(contents) }
            if scalar.isTOMLNewline { throw failure("unterminated string") }
            if quote == "\"" && scalar == "\\" {
                advance()
                contents.append(try escape())
                continue
            }
            contents.append(scalar)
            advance()
        }
        throw failure("unterminated string")
    }

    /// Kept verbatim, escapes included: no layout key is written as a multi-line string.
    private mutating func multilineString(quote: Unicode.Scalar) throws -> String {
        let delimiter = [quote, quote, quote]
        for _ in delimiter { advance() }
        if peek() == "\r" { advance() }
        if peek() == "\n" { advance() }
        var contents = String.UnicodeScalarView()
        while let scalar = peek() {
            if matches(delimiter) {
                for _ in delimiter { advance() }
                return String(contents)
            }
            contents.append(scalar)
            advance()
        }
        throw failure("unterminated multi-line string")
    }

    private mutating func escape() throws -> Unicode.Scalar {
        guard let scalar = peek() else { throw failure("unterminated escape sequence") }
        advance()
        if let simple = scalar.tomlSimpleEscape { return simple }
        switch scalar {
        case "x":
            return try hexEscape(digits: 2)
        case "u":
            return try hexEscape(digits: 4)
        case "U":
            return try hexEscape(digits: 8)
        default:
            throw failure("invalid escape '\\\(scalar.tomlDescription)'")
        }
    }

    private mutating func hexEscape(digits: Int) throws -> Unicode.Scalar {
        var hex = ""
        for _ in 0..<digits {
            guard let digit = peek(), digit.properties.isASCIIHexDigit else {
                throw failure("expected \(digits) hexadecimal digits in an escape")
            }
            hex.unicodeScalars.append(digit)
            advance()
        }
        guard let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) else {
            throw failure("escape '\(hex)' is not a unicode scalar value")
        }
        return scalar
    }

    // MARK: - Trivia

    private mutating func skipSpaces() {
        while let scalar = peek(), scalar.isTOMLSpace { advance() }
    }

    /// Whitespace, newlines and comments — everything that carries no meaning between tokens.
    mutating func skipInsignificant() {
        while let scalar = peek() {
            if scalar.isTOMLWhitespace {
                advance()
            } else if scalar == "#" {
                skipComment()
            } else {
                return
            }
        }
    }

    private mutating func skipComment() {
        while let scalar = peek(), !scalar.isTOMLNewline { advance() }
    }

    private mutating func endOfLine() throws {
        skipSpaces()
        if peek() == "#" { skipComment() }
        guard let scalar = peek() else { return }
        guard scalar.isTOMLNewline else {
            throw failure("unexpected '\(scalar.tomlDescription)' after a value")
        }
        advance()
        if scalar == "\r" && peek() == "\n" { advance() }
    }

    // MARK: - Primitives

    private func peek(offset: Int = 0) -> Unicode.Scalar? {
        index + offset < scalars.count ? scalars[index + offset] : nil
    }

    private func matches(_ expected: [Unicode.Scalar]) -> Bool {
        guard index + expected.count <= scalars.count else { return false }
        return scalars[index..<(index + expected.count)].elementsEqual(expected)
    }

    /// A `\r\n` pair counts as one line break, on its `\n`.
    private mutating func advance() {
        guard let scalar = peek() else { return }
        if scalar == "\n" || (scalar == "\r" && peek(offset: 1) != "\n") {
            line += 1
            column = 1
        } else {
            column += 1
        }
        index += 1
    }

    private mutating func match(_ scalar: Unicode.Scalar) -> Bool {
        skipSpaces()
        guard peek() == scalar else { return false }
        advance()
        return true
    }

    private mutating func expect(_ scalar: Unicode.Scalar) throws {
        guard match(scalar) else {
            throw failure("expected '\(scalar)'")
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

extension Unicode.Scalar {
    var isTOMLQuote: Bool { self == "\"" || self == "'" }
    var isTOMLNewline: Bool { self == "\n" || self == "\r" }
    var isTOMLSpace: Bool { self == " " || self == "\t" }
    var isTOMLWhitespace: Bool { isTOMLSpace || isTOMLNewline }
    var isTOMLBareKey: Bool {
        properties.isAlphabetic || properties.numericType != nil || self == "_" || self == "-"
    }

    var tomlDescription: String { escaped(asASCII: false) }

    /// The escapes that stand for a fixed scalar, as opposed to the hex forms.
    var tomlSimpleEscape: Unicode.Scalar? {
        switch self {
        case "n":
            "\n"
        case "t":
            "\t"
        case "r":
            "\r"
        case "b":
            "\u{08}"
        case "f":
            "\u{0C}"
        case "e":
            "\u{1B}"
        case "\"", "\\", "/":
            self
        default:
            nil
        }
    }
}
