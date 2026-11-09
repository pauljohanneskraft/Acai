import AcaiCore

extension Member {
    /// The parameter list the call graph keys this member's node on — `"(name:String,size:Int)"`,
    /// `"(String,int)"`, `"(_,_)"`, `"()"` — or `nil` for a member that declares no parameter list at
    /// all, so a property and a no-argument method of the same name stay distinct nodes.
    ///
    /// Each parameter contributes whatever the language records for it: its external label and its
    /// simple type name where both are known, one of them where only one is, `_` where neither is.
    /// Both matter — a type list cannot tell Swift's `move(to:)` from `move(from:)`, and a label list
    /// cannot tell one unlabelled Java overload from another.
    var callGraphParameterList: String? {
        guard kind != .property else { return nil }
        return "(" + parameters.map(\.callGraphToken).joined(separator: ",") + ")"
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

extension Parameter {
    /// How this parameter reads inside ``Member/callGraphParameterList``.
    var callGraphToken: String {
        let label = externalName.flatMap { $0.isEmpty ? nil : "\($0):" }
        switch (label, type?.name) {
        case (let label?, let type?):
            return label + type
        case (let label?, nil):
            return label
        case (nil, let type?):
            return type
        case (nil, nil):
            return "_"
        }
    }
}
