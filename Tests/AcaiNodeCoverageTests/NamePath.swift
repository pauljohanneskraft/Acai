import AcaiTreeSitter

/// Where a node of one kind carries the name it declares: a chain of steps narrowing to children
/// either by Tree-sitter field or by node kind, taking every match — one `field_declaration` with
/// three declarators yields three names.
struct NamePath: Sendable {

    enum Step: Sendable {
        /// Every child bound to this field.
        case field(String)
        /// Every direct child of this kind, for a grammar that names no fields.
        case kind(String)
        /// Follows the field while a child is still bound to it, which is how a C declarator chain
        /// (`pointer_declarator` → `function_declarator` → `identifier`) nests.
        case chain(String)
    }

    let steps: [Step]
    /// The name the extractor synthesizes when the grammar leaves the declaration unnamed — a
    /// Kotlin `secondary_constructor` becomes an `init` member.
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
            }
        }
    }
}

extension Node {

    /// Every child bound to `field`, unlike `child(byFieldName:)`, which stops at the first — a
    /// grammar may bind several declarators to one field.
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
