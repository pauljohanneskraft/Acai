/// Hands out the names and ids of one generated artifact. Ids stay unique even when two types draw
/// the same name from the alphabet — a duplicated *simple* name is realistic and is exactly what
/// type-identity resolution has to cope with, but a duplicated `id` would make the artifact invalid.
struct TypeNamer {
    let alphabet: TypeNameAlphabet

    private var namespaces: [String] = []
    private var usedIDs: Set<String> = []
    private(set) var assignedIDs: [String] = []

    init(alphabet: TypeNameAlphabet) {
        self.alphabet = alphabet
    }

    var currentNamespace: String? { namespaces.last }

    mutating func push(namespace: String) {
        namespaces.append(namespace)
    }

    mutating func pop() {
        namespaces.removeLast()
    }

    mutating func nextName(random: inout SeededGenerator) -> String {
        random.pick(alphabet.names) ?? "Unnamed"
    }

    /// Any name from the alphabet, for a reference rather than a declaration — so a relationship or
    /// member type sometimes hits a declared type and sometimes an external one.
    mutating func anyName(random: inout SeededGenerator) -> String {
        random.pick(alphabet.names) ?? "Unnamed"
    }

    /// A unique id for a declaration, suffixed only when the natural id is already taken.
    mutating func assignID(name: String, namespace: String?) -> String {
        let base = namespace.map { "\($0).\(name)" } ?? name
        var candidate = base.isEmpty ? "Unnamed" : base
        var suffix = 2
        while !usedIDs.insert(candidate).inserted {
            candidate = "\(base.isEmpty ? "Unnamed" : base)#\(suffix)"
            suffix += 1
        }
        assignedIDs.append(candidate)
        return candidate
    }
}
