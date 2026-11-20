import AcaiCore

extension Member {
    /// `"(name:String,size:Int)"`, `"(_,_)"`, `"()"`; `nil` for a property, so it never collides with a method.
    var callGraphParameterList: String? {
        guard kind != .property else { return nil }
        return "(" + parameters.map(\.callGraphToken).joined(separator: ",") + ")"
    }

    func acceptsArgumentCount(_ count: Int) -> Bool {
        let required = parameters.filter { $0.defaultValue == nil && !$0.isVariadic }.count
        guard count >= required else { return false }
        return parameters.contains(where: \.isVariadic) || count <= parameters.count
    }

    /// An unlabelled argument matches any parameter.
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
