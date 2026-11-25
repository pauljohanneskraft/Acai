import AcaiCore

/// How a `TypeReference` could have been written, richest spelling first.
struct TypeSpelling {
    let reference: TypeReference
    let sugarsGenericCollections: Bool

    /// The preferred spelling, used when this reference is a generic argument of another.
    var preferred: String { candidates.first ?? reference.name }

    var candidates: [String] {
        bases.flatMap { base in
            reference.isOptional ? ["\(base)?", base] : [base]
        }
    }

    private var bases: [String] {
        sugared + generic + [reference.name]
    }

    private var arguments: [String] {
        reference.genericArguments.map {
            TypeSpelling(reference: $0, sugarsGenericCollections: sugarsGenericCollections).preferred
        }
    }

    /// `[T]` and `[K: V]`, the spellings a sugaring language uses in place of the generic form.
    private var sugared: [String] {
        guard sugarsGenericCollections else { return [] }
        let arguments = self.arguments
        if reference.isArray, arguments.count == 1 {
            return ["[\(arguments[0])]"]
        }
        if arguments.count == 2 {
            return ["[\(arguments[0]):\(arguments[1])]"]
        }
        return []
    }

    /// Both bracket styles: angle brackets everywhere, square brackets in Python's subscript form.
    private var generic: [String] {
        let arguments = self.arguments
        guard !arguments.isEmpty else { return [] }
        let joined = arguments.joined(separator: ",")
        return ["\(reference.name)<\(joined)>", "\(reference.name)[\(joined)]"]
    }
}
