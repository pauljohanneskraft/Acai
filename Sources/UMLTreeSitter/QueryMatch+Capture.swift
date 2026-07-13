@preconcurrency import SwiftTreeSitter

extension QueryMatch {
    /// The single capture named `name` in this match, or `nil` (a match may legitimately carry zero
    /// or one of an optional capture, e.g. `@type.access`).
    func capture(named name: String) -> QueryCapture? {
        captures(named: name).first
    }
}

/// A declaration that can be decorated/annotated (`@Foo class C`, `@decorator def f()`) is naturally
/// matched by *two* query patterns — a bare one and one anchored under the decorator wrapper — since
/// a decorated node still satisfies the bare pattern too. Rather than special-case that in every
/// language's query, this keeps one match per underlying node: the one with the most captures (the
/// decorator-wrapped pattern, when both matched, since it captures everything the bare one does plus
/// the decorator).
func dedupedByCaptureNode(_ matches: [QueryMatch], captureName: String) -> [QueryMatch] {
    var bestByRange: [Range<UInt32>: QueryMatch] = [:]
    var order: [Range<UInt32>] = []
    for match in matches {
        guard let range = match.capture(named: captureName)?.node.byteRange else { continue }
        if let existing = bestByRange[range] {
            if match.captures.count > existing.captures.count { bestByRange[range] = match }
        } else {
            bestByRange[range] = match
            order.append(range)
        }
    }
    return order.compactMap { bestByRange[$0] }
}

/// A node with its byte range precomputed, so containment checks (`assignToInnermostContainer`)
/// don't repeatedly recompute `Node.byteRange`.
struct RangedNode: Sendable {
    let node: Node
    let range: Range<UInt32>

    init(_ node: Node) {
        self.node = node
        self.range = node.byteRange
    }
}

/// A value with a source byte range, so `groupedByInnermostType` can bucket members/enum cases by
/// their innermost enclosing `@type` capture regardless of which of those two it's grouping.
protocol RangedElement {
    var range: Range<UInt32> { get }
}

extension AssembledMember: RangedElement {}
extension AssembledEnumCase: RangedElement {}

/// Buckets `elements` by the innermost of `typeNodes` containing each one's range; an element inside
/// no type node is returned separately (a top-level declaration).
func groupedByInnermostType<Element: RangedElement>(
    _ elements: [Element], typeNodes: [RangedNode]
) -> (byType: [Int: [Element]], topLevel: [Element]) {
    var byType: [Int: [Element]] = [:]
    var topLevel: [Element] = []
    for element in elements {
        if let index = innermostContainerIndex(containing: element.range, in: typeNodes) {
            byType[index, default: []].append(element)
        } else {
            topLevel.append(element)
        }
    }
    return (byType, topLevel)
}

/// The index, among `containers`, of the smallest container whose range strictly contains `range`
/// (used to attribute a member/enum-case/nested-type to its innermost enclosing type). `nil` when no
/// container encloses it (a top-level declaration).
func innermostContainerIndex(containing range: Range<UInt32>, in containers: [RangedNode], excluding: Int? = nil) -> Int? {
    var best: Int?
    for (index, container) in containers.enumerated() {
        guard index != excluding, container.range != range,
              container.range.lowerBound <= range.lowerBound, container.range.upperBound >= range.upperBound
        else { continue }
        if let bestIndex = best {
            if container.range.count < containers[bestIndex].range.count { best = index }
        } else {
            best = index
        }
    }
    return best
}
