import AcaiTreeSitter

/// Where a node of one kind carries the name it declares, as steps narrowing to matching children.
struct NamePath: Sendable {

    enum Step: Sendable {
        /// Every child bound to this field.
        case field(String)
        /// Every direct child of this kind, for a grammar that names no fields.
        case kind(String)
        /// Follows the field while a child is still bound to it, as a C declarator chain nests.
        case chain(String)
        /// The first direct child of any of these kinds, where a grammar flattens the initializer in.
        case first([String])
        /// The last direct child of any of these kinds, as `Counter.unlimited` names itself last.
        case last([String])
    }

    let steps: [Step]
    /// The name the extractor synthesizes when the grammar leaves the declaration unnamed.
    let synthesizedName: String?

    init(_ steps: Step..., synthesizedName: String? = nil) {
        self.steps = steps
        self.synthesizedName = synthesizedName
    }

    /// The names this path reads out of `node`, each with the line its site sits on.
    func names(of node: Node, in context: SourceFileContext) -> [(name: String, line: Int)] {
        sites(from: node).map { site in
            (synthesizedName ?? site.text(in: context), site.location(in: context).line)
        }
    }

    private func sites(from node: Node) -> [Node] {
        steps.reduce([node]) { sites, step in
            switch step {
            case .field(let field):
                return sites.flatMap { $0.children(boundTo: field) }
            case .kind(let kind):
                return sites.flatMap { $0.children().filter { $0.nodeType == kind } }
            case .chain(let field):
                return sites.compactMap { $0.followingChain(of: field) }
            case .first(let kinds):
                return sites.compactMap { $0.children().first { kinds.contains($0.nodeType ?? "") } }
            case .last(let kinds):
                return sites.compactMap { $0.children().last { kinds.contains($0.nodeType ?? "") } }
            }
        }
    }
}

extension Node {

    /// Every child bound to `field`, unlike `child(byFieldName:)`, which stops at the first.
    func children(boundTo field: String) -> [Node] {
        (0..<childCount).compactMap { index in
            fieldNameForChild(at: index) == field ? child(at: index) : nil
        }
    }

    fileprivate func followingChain(of field: String) -> Node? {
        guard var node = children(boundTo: field).first else { return nil }
        while let next = node.children(boundTo: field).first {
            node = next
        }
        return node
    }
}
