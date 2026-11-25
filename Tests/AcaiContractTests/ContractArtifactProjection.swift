import Foundation
import AcaiCore

/// What a source variation is allowed to change about an artifact besides the file it came from.
struct ContractEquivalenceTolerance: Equatable {
    /// Lines the variation moves every declaration by; columns always have to stay put.
    var lineOffset = 0
    /// Set when the variation moves declarations by an amount that is not uniform.
    var ignoresLocations = false
    /// Set when the variation changes the order declarations appear in, but not the set of them.
    var ignoresDeclarationOrder = false
}

/// Rewrites an encoded artifact into the form one tolerance compares.
///
/// `filePath` is erased wherever it appears, because a variation has to rename the file to change its
/// extension and because the corpus parses from `#filePath`, which differs per checkout. A
/// `SourceLocation` — the one object carrying `filePath`, `line` and `column` together — is then
/// shifted or dropped as the tolerance says.
struct ContractJSONRewriter {
    let tolerance: ContractEquivalenceTolerance
    let erasedPath = "<path>"

    /// The arrays a second snippet appends to. Nothing else is sorted: a type's members and a
    /// declaration's modifiers keep their source order, which is part of what is being checked.
    let unorderedKeys: Set<String> = [
        "types", "relationships", "freestandingFunctions", "globalVariables", "parseDiagnostics"
    ]

    func rewritten(_ node: ContractJSON, key: String? = nil) -> ContractJSON {
        switch node {
        case .object(let fields):
            return .object(rewritten(fields: fields))
        case .array(let elements):
            return .array(rewritten(elements: elements, key: key))
        case .string where key == "filePath":
            return .string(erasedPath)
        default:
            return node
        }
    }

    private func rewritten(elements: [ContractJSON], key: String?) -> [ContractJSON] {
        let rewritten = elements.map { self.rewritten($0, key: key) }
        if key == "filePaths" {
            return rewritten.isEmpty ? [] : [.string(erasedPath)]
        }
        guard tolerance.ignoresDeclarationOrder, unorderedKeys.contains(key ?? "") else { return rewritten }
        return rewritten.sorted { $0.canonicalText < $1.canonicalText }
    }

    private func rewritten(fields: [String: ContractJSON]) -> [String: ContractJSON] {
        var result = fields.reduce(into: [String: ContractJSON]()) { result, field in
            result[field.key] = rewritten(field.value, key: field.key)
        }
        guard fields["filePath"] != nil, fields["line"] != nil, fields["column"] != nil else { return result }
        if tolerance.ignoresLocations {
            for key in ["line", "column", "endLine"] { result[key] = nil }
            return result
        }
        for key in ["line", "endLine"] {
            guard case .number(let value) = result[key] else { continue }
            result[key] = .number(value + Double(tolerance.lineOffset))
        }
        return result
    }
}

/// A `CodeArtifact` reduced to what an equivalence check compares: everything except the file it was
/// read from, plus whatever the variation's tolerance excuses.
struct ContractArtifactProjection: Equatable, CustomStringConvertible {
    let json: ContractJSON

    init(artifact: CodeArtifact, tolerance: ContractEquivalenceTolerance = .init()) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(artifact)
        let tree = ContractJSON(jsonObject: try JSONSerialization.jsonObject(with: data))
        json = ContractJSONRewriter(tolerance: tolerance).rewritten(tree)
    }

    /// The artifacts a joined snippet has to add up to, as one value.
    init(union artifacts: [CodeArtifact], tolerance: ContractEquivalenceTolerance) throws {
        guard var merged = artifacts.first else { throw ContractEquivalenceFailure.emptyUnion }
        for artifact in artifacts.dropFirst() {
            merged.types += artifact.types
            merged.relationships += artifact.relationships
            merged.freestandingFunctions += artifact.freestandingFunctions
            merged.globalVariables += artifact.globalVariables
            merged.metadata.filePaths += artifact.metadata.filePaths
            merged.metadata.parseDiagnostics += artifact.metadata.parseDiagnostics
        }
        try self.init(artifact: merged, tolerance: tolerance)
    }

    var description: String { json.canonicalText }
}

enum ContractEquivalenceFailure: Error, CustomStringConvertible {
    case emptyUnion
    case noDisjointPartner(feature: String, language: String)

    var description: String {
        switch self {
        case .emptyUnion:
            return "a joined snippet was compared against no artifacts at all"
        case .noDisjointPartner(let feature, let language):
            return "no other \(language) snippet declares names disjoint from '\(feature)', so the "
                + "join variation has nothing to append; it is skipped for this snippet."
        }
    }
}
