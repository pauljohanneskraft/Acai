import AcaiCore
import AcaiTreeSitter
import Foundation

/// The declaration-site variance TypeScript 4.7 writes as `in`/`out` before a type parameter's
/// name, recovered from a grammar that does not model it.
///
/// The vendored grammar's `type_parameter` has `const` as its only modifier slot, so it takes an
/// `in`/`out` modifier *as* the parameter's name and recovers the real name into an `ERROR` node:
/// `interface Producer<out T>` reaches the model as a parameter named `out`, and the file is
/// flagged as unparseable. Blanking each modifier with spaces leaves every other offset in the
/// file untouched, so a parse of ``rewrittenSource`` reads the list correctly, and
/// ``variance(of:)`` carries back what blanking removed, keyed on the name's offset.
///
/// This recovers, rather than reads, the broken parse: the name comes from a tree with no `ERROR`
/// in it. A grammar that models the modifiers never records a parameter *named* `in` or `out`, so
/// the day the vendored one gains them this finds nothing and rewrites nothing.
struct TypeScriptVarianceModifiers {

    /// `source` with every mis-parsed modifier blanked, or `source` unchanged when there were none.
    let rewrittenSource: String

    private let variances: [Int: Variance]

    init(source: String, fileName: String, grammar: TreeSitterGrammar) {
        let scan = VarianceModifierScan(context: SourceFileContext(source: source, fileName: fileName))
        let modifiers = scan.modifiers(parsedBy: grammar)
        guard !modifiers.isEmpty else {
            rewrittenSource = source
            variances = [:]
            return
        }
        let blanked = NSMutableString(string: source)
        // Each replacement is the same length as what it replaces, so the ranges stay valid as they
        // are applied and every offset outside them is the offset it was.
        for range in modifiers.flatMap(\.blankedRanges) {
            blanked.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
        }
        rewrittenSource = blanked as String
        variances = Dictionary(modifiers.map { ($0.nameOffset, $0.variance) }) { first, _ in first }
    }

    /// For JavaScript, which has no type parameters to mis-parse.
    init(unmodified source: String) {
        rewrittenSource = source
        variances = [:]
    }

    /// The variance declared before `nameNode`, which must come from a tree over
    /// ``rewrittenSource`` — the offsets are what ties the two together.
    func variance(of nameNode: Node) -> Variance? {
        variances[nameNode.range.location]
    }
}

/// One type parameter whose modifiers the grammar mis-parsed: the variance they declared, the
/// offset of the name they were written before, and the ranges to blank so that name is read.
private struct VarianceModifier {
    let variance: Variance
    let nameOffset: Int
    let blankedRanges: [NSRange]
}

/// The first pass over a file, looking for modifiers the grammar mis-parsed.
private struct VarianceModifierScan {
    let context: SourceFileContext

    private static let keywords: Set<String> = ["in", "out"]

    /// A mis-parse needs `in` or `out` as a type parameter's first token, so a file with neither
    /// word directly after a `<` or a `,` cannot hold one.
    private var isPossible: Bool {
        context.source.range(of: #"[<,]\s*(in|out)\s"#, options: .regularExpression) != nil
    }

    /// Empty whenever the file cannot hold a mis-parsed modifier, which is the common case — the
    /// textual check comes first so that an ordinary file is not parsed twice.
    func modifiers(parsedBy grammar: TreeSitterGrammar) -> [VarianceModifier] {
        guard isPossible,
              let parser = grammar.makeParser(),
              let tree = parser.parse(context.source),
              let root = tree.rootNode,
              root.hasError
        else { return [] }
        return modifiers(in: root)
    }

    private func modifiers(in root: Node) -> [VarianceModifier] {
        var found: [VarianceModifier] = []
        func walk(_ node: Node) {
            if node.nodeType == "type_parameters" { found.append(contentsOf: modifiers(inList: node)) }
            for index in 0..<node.childCount { node.child(at: index).map(walk) }
        }
        walk(root)
        return found
    }

    private func modifiers(inList list: Node) -> [VarianceModifier] {
        let children = list.namedChildren()
        return children.indices.compactMap { index in
            guard children[index].nodeType == "type_parameter" else { return nil }
            let next = index + 1 < children.count ? children[index + 1] : nil
            return modifier(for: children[index], followedBy: next)
        }
    }

    /// Nil unless the parameter's recorded name is a variance keyword *and* a real name was
    /// recovered beside it: `interface Sink<out>` really does declare a parameter named `out`.
    private func modifier(for parameter: Node, followedBy next: Node?) -> VarianceModifier? {
        guard let nameNode = parameter.child(byFieldName: "name") ?? parameter.namedChildren().first,
              Self.keywords.contains(nameNode.text(in: context))
        else { return nil }
        // The real name lands in an `ERROR` node — nested in the parameter when it also carries a
        // constraint or a default type, its next sibling when it does not.
        let recovery = parameter.namedChildren().first { $0.nodeType == "ERROR" }
            ?? next.flatMap { $0.nodeType == "ERROR" ? $0 : nil }
        guard let recovery else { return nil }
        let recovered = recovery.namedChildren().filter { $0.nodeType == "identifier" }
        guard let name = recovered.last, !Self.keywords.contains(name.text(in: context)) else { return nil }

        // Everything the recovery holds before the name has to be a keyword too — `in out T`
        // recovers both the second modifier and the name into one node.
        var keywords: Set<String> = [nameNode.text(in: context)]
        var blanked = [nameNode.range]
        for leading in recovered.dropLast() {
            let text = leading.text(in: context)
            guard Self.keywords.contains(text) else { return nil }
            keywords.insert(text)
            blanked.append(leading.range)
        }
        guard let variance = variance(declaredBy: keywords) else { return nil }
        return VarianceModifier(variance: variance, nameOffset: name.range.location, blankedRanges: blanked)
    }

    private func variance(declaredBy keywords: Set<String>) -> Variance? {
        switch keywords.sorted() {
        case ["out"]: .covariant
        case ["in"]: .contravariant
        case ["in", "out"]: .invariant
        default: nil
        }
    }
}
