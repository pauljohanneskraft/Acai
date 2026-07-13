@preconcurrency import SwiftTreeSitter
import UMLCore

/// An enum case assembled from one `@enumCase` query match, alongside its source range (for
/// attributing it to the innermost enclosing `@type`).
struct AssembledEnumCase: Sendable {
    var enumCase: EnumCase
    var range: Range<UInt32>
}

/// `@enumCase.*` captures → `[AssembledEnumCase]`.
struct EnumCaseAssembler: Sendable {
    func assemble(_ matches: [QueryMatch], source: ParsedSource) -> [AssembledEnumCase] {
        matches.compactMap { assemble($0, source: source) }
    }

    private func assemble(_ match: QueryMatch, source: ParsedSource) -> AssembledEnumCase? {
        guard let caseCapture = match.capture(named: "enumCase"),
              let nameCapture = match.capture(named: "enumCase.name")
        else { return nil }
        let enumCase = EnumCase(
            name: nameCapture.node.text(in: source),
            rawValue: match.capture(named: "enumCase.rawValue")?.node.text(in: source),
            location: caseCapture.node.location(in: source))
        return AssembledEnumCase(enumCase: enumCase, range: caseCapture.node.byteRange)
    }
}
