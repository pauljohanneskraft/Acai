import AcaiCore

extension Member {
    /// The parameter list the call graph keys this member's node on — `"(from:to:)"`,
    /// `"(String,int)"`, `"(_,_)"` or `"()"` — or `nil` for a member that declares no parameter list
    /// at all, so a property and a no-argument method of the same name stay distinct nodes.
    ///
    /// The spelling follows what the language records: external labels where it has them, simple
    /// parameter type names where it records types instead, `_` where it records neither. Rendering
    /// the whole list one way, rather than per parameter, keeps the key legible as a diagram label.
    var callGraphParameterList: String? {
        guard kind != .property else { return nil }
        guard !parameters.isEmpty else { return "()" }
        if parameters.contains(where: { $0.externalName?.isEmpty == false }) {
            return "(" + parameters.map { "\($0.externalName ?? "_"):" }.joined() + ")"
        }
        if parameters.contains(where: { $0.type != nil }) {
            return "(" + parameters.map { $0.type?.name ?? "_" }.joined(separator: ",") + ")"
        }
        return "(" + parameters.map { _ in "_" }.joined(separator: ",") + ")"
    }

    /// Whether a call passing `count` arguments could be a call to this member: a parameter with a
    /// default value may be omitted, and a variadic parameter absorbs any number of extras.
    func acceptsArgumentCount(_ count: Int) -> Bool {
        let required = parameters.filter { $0.defaultValue == nil && !$0.isVariadic }.count
        guard count >= required else { return false }
        return parameters.contains(where: \.isVariadic) || count <= parameters.count
    }

    /// Whether a call's argument `labels` are positionally consistent with this member's parameter
    /// labels. An entry the call spells no label for matches any parameter, so a language without
    /// argument labels neither gains nor loses candidates here; a count mismatch (an omitted
    /// defaulted parameter shifts every later position) is not something positions can judge.
    func matchesArgumentLabels(_ labels: [String?]) -> Bool {
        guard labels.count == parameters.count else { return false }
        return zip(labels, parameters).allSatisfy { label, parameter in
            guard let label else { return true }
            return label == parameter.externalName
        }
    }
}
