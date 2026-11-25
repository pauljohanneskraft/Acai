import Foundation

/// Swift source text, walked outside its string literals and comments, where a `?` is never a ternary.
struct TopLevelScan {

    struct Position {
        let index: Substring.Index
        let character: Character
        /// Bracket depth after this character; -1 closes a bracket opened before `text`.
        let depth: Int
    }

    let text: Substring

    var positions: [Position] {
        var positions: [Position] = []
        walk {
            positions.append($0)
            return true
        }
        return positions
    }

    func firstPosition(where match: (Position) -> Bool) -> Position? {
        var found: Position?
        walk {
            guard match($0) else { return true }
            found = $0
            return false
        }
        return found
    }

    /// The text between the `(` at `open` and its matching `)`.
    func callContents(openedAt open: Substring.Index) -> Substring {
        let inner = text[text.index(after: open)...]
        let scan = TopLevelScan(text: inner)
        guard let close = scan.firstPosition(where: { $0.character == ")" && $0.depth < 0 }) else { return inner }
        return inner[..<close.index]
    }

    /// The index just past the string literal starting at `start`, its interpolations included.
    func literalEnd(from start: Substring.Index) -> Substring.Index {
        var index = text.index(after: start)
        while index < text.endIndex {
            if text[index] == "\\" {
                index = escapeEnd(from: index)
                continue
            }
            if text[index] == "\"" { return text.index(after: index) }
            index = text.index(after: index)
        }
        return text.endIndex
    }

    private func walk(_ visit: (Position) -> Bool) {
        var index = text.startIndex
        var depth = 0
        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                index = literalEnd(from: index)
                continue
            }
            if let end = commentEnd(from: index) {
                index = end
                continue
            }
            if "([{".contains(character) { depth += 1 }
            if ")]}".contains(character) { depth -= 1 }
            guard visit(Position(index: index, character: character, depth: depth)) else { return }
            index = text.index(after: index)
        }
    }

    private func escapeEnd(from backslash: Substring.Index) -> Substring.Index {
        let next = text.index(after: backslash)
        guard next < text.endIndex else { return text.endIndex }
        guard text[next] == "(" else { return text.index(after: next) }
        return interpolationEnd(from: next)
    }

    private func interpolationEnd(from open: Substring.Index) -> Substring.Index {
        var depth = 0
        var index = open
        while index < text.endIndex {
            if text[index] == "\"" {
                index = literalEnd(from: index)
                continue
            }
            if text[index] == "(" { depth += 1 }
            if text[index] == ")" {
                depth -= 1
                if depth == 0 { return text.index(after: index) }
            }
            index = text.index(after: index)
        }
        return text.endIndex
    }

    private func commentEnd(from start: Substring.Index) -> Substring.Index? {
        guard text[start] == "/" else { return nil }
        let next = text.index(after: start)
        guard next < text.endIndex else { return nil }
        if text[next] == "/" { return text[next...].firstIndex(of: "\n") ?? text.endIndex }
        guard text[next] == "*" else { return nil }
        return text.range(of: "*/", range: next..<text.endIndex)?.upperBound ?? text.endIndex
    }
}

struct StringLiteral {

    let text: Substring

    /// `""` is the one literal a localizable position may take: it labels an unlabelled control.
    var isEmpty: Bool { text == "\"\"" }

    /// The part of the literal fixed at the call site — every `\(…)` and escape removed.
    var constantText: String {
        let end = TopLevelScan(text: text).literalEnd(from: text.startIndex)
        let closingQuote = text.index(before: end)
        var constant = ""
        var index = text.index(after: text.startIndex)
        while index < closingQuote {
            guard text[index] == "\\" else {
                constant.append(text[index])
                index = text.index(after: index)
                continue
            }
            index = skipEscape(from: index)
        }
        return constant
    }

    private func skipEscape(from backslash: Substring.Index) -> Substring.Index {
        let next = text.index(after: backslash)
        guard next < text.endIndex else { return text.endIndex }
        guard text[next] == "(" else { return text.index(after: next) }
        var depth = 0
        var index = next
        while index < text.endIndex {
            if text[index] == "(" { depth += 1 }
            if text[index] == ")" {
                depth -= 1
                if depth == 0 { return text.index(after: index) }
            }
            index = text.index(after: index)
        }
        return text.endIndex
    }
}

/// A Swift expression and the literals it can evaluate to: itself, or the branches of its `?:`/`??`.
struct LiteralExpression {

    let text: Substring

    var literals: [StringLiteral] {
        let expression = text.drop { $0.isWhitespace }
        guard let first = expression.first else { return [] }
        guard first != "\"" else {
            let end = TopLevelScan(text: expression).literalEnd(from: expression.startIndex)
            return [StringLiteral(text: expression[..<end])]
        }
        return branches.flatMap { LiteralExpression(text: $0).literals }
    }

    private var branches: [Substring] {
        let expression = text.drop { $0.isWhitespace }
        let positions = TopLevelScan(text: expression).positions.filter { $0.depth == 0 }
        return ternaryBranches(of: expression, positions) ?? coalescedBranches(of: expression, positions) ?? []
    }

    private func ternaryBranches(
        of expression: Substring,
        _ positions: [TopLevelScan.Position]
    ) -> [Substring]? {
        guard let question = positions.firstIndex(where: { isTernaryQuestion($0, in: expression) }) else {
            return nil
        }
        var nested = 0
        for position in positions[positions.index(after: question)...] {
            if isTernaryQuestion(position, in: expression) {
                nested += 1
                continue
            }
            guard position.character == ":" else { continue }
            guard nested == 0 else {
                nested -= 1
                continue
            }
            let colon = position.index
            return [
                expression[expression.index(after: positions[question].index)..<colon],
                expression[expression.index(after: colon)...]
            ]
        }
        return nil
    }

    private func coalescedBranches(
        of expression: Substring,
        _ positions: [TopLevelScan.Position]
    ) -> [Substring]? {
        for position in positions where position.character == "?" {
            let next = expression.index(after: position.index)
            guard next < expression.endIndex, expression[next] == "?" else { continue }
            return [expression[..<position.index], expression[expression.index(after: next)...]]
        }
        return nil
    }

    /// A `?` that opens a ternary rather than an optional type, an optional chain, `as?` or `try?`.
    private func isTernaryQuestion(_ position: TopLevelScan.Position, in expression: Substring) -> Bool {
        guard position.character == "?" else { return false }
        let next = expression.index(after: position.index)
        guard next < expression.endIndex, expression[next] == " " || expression[next] == "\n" else { return false }
        let preceding = expression[..<position.index].reversed().drop { $0 == " " }
        let word = String(preceding.prefix { $0.isLetter }.reversed())
        return word != "as" && word != "try"
    }
}

/// One Swift file of `AcaiApp`, and the localizable positions in it that take a literal.
struct BareLiteralScan {

    struct Violation {
        let position: String
        /// The literal with every interpolation removed, which is what would have to be translated.
        let text: String
    }

    /// A localizable position: whatever it is handed reaches the interface as chrome.
    static let chromePositions = [
        "Text(", "Label(", "Button(", "Toggle(", "Picker(", "TextField(", "SecureField(",
        "Section(", "Menu(", "Link(", "NavigationLink(", "LabeledContent(", "DisclosureGroup(",
        "Stepper(", "ProgressView(", "ContentUnavailableView(", "TableColumn(", "GroupBox(",
        ".help(", ".navigationTitle(", ".accessibilityLabel(", ".accessibilityHint(",
        ".accessibilityValue(", ".alert(", ".confirmationDialog("
    ]

    static let verbatimPosition = "Text(verbatim:"

    let source: String

    /// Every index of `source` that is code, so a position named in a comment is not read as a call.
    private let codeIndices: Set<String.Index>

    init(source: String) {
        self.source = source
        self.codeIndices = Set(TopLevelScan(text: Substring(source)).positions.map(\.index))
    }

    /// Every literal a chrome position takes; a labelled first argument says the `Text` is not chrome.
    var chromeViolations: [Violation] {
        Self.chromePositions.flatMap { position in
            arguments(after: position)
                .filter { label(of: $0) == nil }
                .flatMap { LiteralExpression(text: $0).literals }
                .filter { !$0.isEmpty }
                .map { Violation(position: position, text: $0.constantText) }
        }
    }

    /// Every `Text(verbatim:)` literal carrying a letter outside its interpolations.
    var verbatimViolations: [Violation] {
        arguments(after: Self.verbatimPosition)
            .map { unlabelled($0) }
            .flatMap { LiteralExpression(text: $0).literals }
            .map { $0.constantText }
            .filter { $0.contains(where: \.isLetter) }
            .map { Violation(position: Self.verbatimPosition, text: $0) }
    }

    /// The first argument of every call to `position` in the file.
    private func arguments(after position: String) -> [Substring] {
        guard let paren = position.firstIndex(of: "(") else { return [] }
        let offset = position.distance(from: position.startIndex, to: paren)
        let scan = TopLevelScan(text: Substring(source))
        var arguments: [Substring] = []
        var searched = source.startIndex
        while let found = source.range(of: position, range: searched..<source.endIndex) {
            searched = found.upperBound
            guard codeIndices.contains(found.lowerBound), isWholeWord(position, at: found.lowerBound) else {
                continue
            }
            let open = source.index(found.lowerBound, offsetBy: offset)
            arguments.append(firstArgument(of: scan.callContents(openedAt: open)))
        }
        return arguments
    }

    /// `Label(` must be the whole word, not the tail of `chartXAxisLabel(`.
    private func isWholeWord(_ position: String, at start: String.Index) -> Bool {
        guard !position.hasPrefix("."), start > source.startIndex else { return true }
        let preceding = source[source.index(before: start)]
        return !(preceding.isLetter || preceding == ".")
    }

    private func firstArgument(of call: Substring) -> Substring {
        let scan = TopLevelScan(text: call)
        guard let comma = scan.firstPosition(where: { $0.character == "," && $0.depth == 0 }) else { return call }
        return call[..<comma.index]
    }

    private func label(of argument: Substring) -> Substring? {
        let trimmed = argument.drop { $0.isWhitespace }
        let identifier = trimmed.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        guard !identifier.isEmpty else { return nil }
        let rest = trimmed[identifier.endIndex...].drop { $0.isWhitespace }
        guard rest.first == ":", rest.dropFirst().first != ":" else { return nil }
        return identifier
    }

    private func unlabelled(_ argument: Substring) -> Substring {
        guard let label = label(of: argument) else { return argument }
        let rest = argument[label.endIndex...].drop { $0.isWhitespace }
        return rest.dropFirst()
    }
}
