import Foundation
import AcaiCore

/// One contract snippet as the equivalence suite reads it.
struct ContractSnippet {
    let feature: String
    let language: ContractFeatureCorpus.Language
    let source: String
    let fileName: String

    var stem: String { fileName.components(separatedBy: ".").first ?? language.stem }
}

/// A snippet rewritten by one variation, plus the artifacts the rewrite adds to the original's.
struct ContractVariedSource {
    var source: String
    var fileName: String
    /// Non-empty only where the variation appends another snippet, whose artifact the varied source
    /// then has to account for as well as the original's.
    var appended: [CodeArtifact] = []
}

/// A rewrite of a snippet that must not change the model, beyond what its ``tolerance`` excuses.
protocol ContractSourceVariation: Sendable, CustomStringConvertible {
    var name: String { get }
    /// The variation this is one case of, so a guardrail can take one case per kind.
    var kind: String { get }
    var tolerance: ContractEquivalenceTolerance { get }

    func varied(_ snippet: ContractSnippet) -> ContractVariedSource
}

extension ContractSourceVariation {
    var description: String { name }
    var kind: String { name }
    var tolerance: ContractEquivalenceTolerance { .init() }
}

/// The same bytes under a shouted extension. A parser that compares `fileName` case-sensitively routes
/// the file to the wrong grammar, or to none (#609).
struct ContractUppercaseExtension: ContractSourceVariation {
    let fileExtension: String

    let kind = "uppercase extension"

    var name: String { "uppercase .\(fileExtension.uppercased())" }

    func varied(_ snippet: ContractSnippet) -> ContractVariedSource {
        ContractVariedSource(source: snippet.source, fileName: "\(snippet.stem).\(fileExtension.uppercased())")
    }
}

/// Windows line endings. The locations are compared too: a `\r` counted as a column, or a line offset
/// measured in UTF-8 bytes, shows up here and nowhere else.
struct ContractCarriageReturnLineEndings: ContractSourceVariation {
    let name = "CRLF line endings"

    func varied(_ snippet: ContractSnippet) -> ContractVariedSource {
        let unixEndings = snippet.source.replacingOccurrences(of: "\r\n", with: "\n")
        return ContractVariedSource(
            source: unixEndings.replacingOccurrences(of: "\n", with: "\r\n"), fileName: snippet.fileName)
    }
}

/// One comment line above everything, holding a non-ASCII letter and an emoji. Every declaration moves
/// down exactly one line and none of them moves sideways, so a line counted from a byte offset rather
/// than from a newline drifts here, and a column rebased on the new first line fails outright.
struct ContractLeadingComment: ContractSourceVariation {
    let name = "a leading comment holding é and 🧪"
    var tolerance: ContractEquivalenceTolerance { .init(lineOffset: 1) }

    func varied(_ snippet: ContractSnippet) -> ContractVariedSource {
        ContractVariedSource(
            source: "\(snippet.language.lineComment) é 🧪\n\(snippet.source)", fileName: snippet.fileName)
    }
}

/// Trailing whitespace on every line, and a blank line after every line that can take one.
///
/// Neither is content, so the snippet still declares exactly what it declared. A blank line is not
/// added after a comment: a doc comment belongs to the declaration directly below it, so a blank line
/// between them detaches it, which is a change of meaning rather than of formatting. Lines inside a
/// literal or a block comment are left exactly as they are, where the added bytes would be text.
struct ContractBlankLinesAndTrailingWhitespace: ContractSourceVariation {
    let name = "extra blank lines and trailing whitespace"
    var tolerance: ContractEquivalenceTolerance { .init(ignoresLocations: true) }

    func varied(_ snippet: ContractSnippet) -> ContractVariedSource {
        var state = ContractSourceLineState()
        var lines: [String] = []
        for line in snippet.source.components(separatedBy: "\n") {
            let classified = state.advanced(over: line, lineComment: snippet.language.lineComment)
            guard classified.isPlainCode else {
                lines.append(line)
                continue
            }
            lines.append("\(line)  ")
            if classified.takesABlankLineAfter { lines.append("") }
        }
        return ContractVariedSource(source: lines.joined(separator: "\n"), fileName: snippet.fileName)
    }
}

/// Walks a snippet line by line, saying for each what reformatting it can take.
struct ContractSourceLineState {
    private var inLiteral = false
    private var inBlockComment = false

    struct Line {
        /// Outside every multi-line literal and block comment, so trailing whitespace is formatting.
        let isPlainCode: Bool
        /// Also not a comment, so a blank line after it detaches nothing.
        let takesABlankLineAfter: Bool
    }

    mutating func advanced(over line: String, lineComment: String) -> Line {
        let wasInLiteral = inLiteral
        let wasInBlockComment = inBlockComment
        let literal = ContractMultilineLiteral(line: line)
        if !literal.delimiterCount.isMultiple(of: 2) { inLiteral.toggle() }
        if !wasInLiteral, !inLiteral {
            inBlockComment = literal.leavesABlockCommentOpen(whenAlreadyOpen: wasInBlockComment)
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let isPlainCode =
            !wasInLiteral && !inLiteral && !wasInBlockComment && !inBlockComment && !trimmed.isEmpty
        let startsAComment = ["/*", "*", "//", lineComment].contains { trimmed.hasPrefix($0) }
        return Line(isPlainCode: isPlainCode, takesABlankLineAfter: isPlainCode && !startsAComment)
    }
}

/// What a line carries of the constructs that run past its end, so a line that opens or closes one can
/// be left untouched.
struct ContractMultilineLiteral {
    let line: String
    let delimiters = ["\"\"\"", "'''", "R\"(", ")\""]

    var delimiterCount: Int {
        delimiters.reduce(0) { count, delimiter in
            count + line.components(separatedBy: delimiter).count - 1
        }
    }

    func leavesABlockCommentOpen(whenAlreadyOpen open: Bool) -> Bool {
        let opened = line.components(separatedBy: "/*").count - 1
        let closed = line.components(separatedBy: "*/").count - 1
        return open ? closed == 0 || opened > closed : opened > closed
    }
}

/// Another feature's snippet, chosen so the two models cannot interfere.
struct ContractJoinPartner: Sendable {
    let feature: String
    let source: String
    let artifact: CodeArtifact
}

/// A second snippet appended to the first, or prepended to it. The two declare no name in common and
/// neither mentions a name the other declares, so the joined file's model has to be exactly the two
/// models together — unrelated code next door changes nothing.
struct ContractJoinedSnippet: ContractSourceVariation {
    let partner: ContractJoinPartner
    let partnerComesFirst: Bool

    let kind = "joined snippet"

    var name: String {
        "joined \(partnerComesFirst ? "after" : "before") \(partner.feature)"
    }

    var tolerance: ContractEquivalenceTolerance {
        .init(ignoresLocations: true, ignoresDeclarationOrder: true)
    }

    func varied(_ snippet: ContractSnippet) -> ContractVariedSource {
        let parts = partnerComesFirst ? [partner.source, snippet.source] : [snippet.source, partner.source]
        return ContractVariedSource(
            source: parts.map { $0.hasSuffix("\n") ? $0 : "\($0)\n" }.joined(separator: "\n"),
            fileName: snippet.fileName,
            appended: [partner.artifact])
    }
}

/// Finds the snippet to join a snippet with: another feature's, in the same language, declaring no
/// name the original declares or mentions, and parsing cleanly on its own.
struct ContractDisjointPartner {
    let feature: String
    let language: ContractFeatureCorpus.Language
    let corpus: ContractFeatureCorpus

    func resolved() throws -> ContractJoinPartner {
        let own = try corpus.snippet(feature: feature, language: language)
        let ownNames = names(in: try corpus.artifact(feature: feature, language: language))
        for candidateFeature in corpus.features where candidateFeature != feature {
            guard let candidate = try? corpus.snippet(feature: candidateFeature, language: language),
                  let artifact = try? corpus.artifact(feature: candidateFeature, language: language),
                  !artifact.metadata.hasParseErrors else { continue }
            let candidateNames = names(in: artifact)
            guard candidateNames.isDisjoint(with: ownNames),
                  !candidateNames.contains(where: { own.source.contains($0) }),
                  !ownNames.contains(where: { candidate.source.contains($0) }) else { continue }
            return ContractJoinPartner(
                feature: candidateFeature, source: candidate.source, artifact: artifact)
        }
        throw ContractEquivalenceFailure.noDisjointPartner(feature: feature, language: language.stem)
    }

    /// Every name the artifact declares, at any depth, plus every endpoint it points at — an
    /// unresolved supertype or a called method the other snippet happens to declare would make the
    /// two models interfere.
    private func names(in artifact: CodeArtifact) -> Set<String> {
        var names = Set(artifact.freestandingFunctions.map(\.name) + artifact.globalVariables.map(\.name))
        names.formUnion(artifact.relationships.flatMap { [$0.source, $0.target] })
        var pending = artifact.types
        while let type = pending.popLast() {
            names.formUnion([type.name, type.qualifiedName, type.id])
            names.formUnion(type.members.map(\.name))
            names.formUnion(type.enumCases.map(\.name))
            pending.append(contentsOf: type.nestedTypes)
        }
        return names.filter { !$0.isEmpty }
    }
}
