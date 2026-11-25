import AcaiCore

/// Holds one parsed artifact to the source it came from: locations, type identity and type spelling.
struct SourceFidelityCheck {
    let text: SourceText
    let artifact: CodeArtifact
    let difference: DeclaredLanguageDifference

    var violations: [FidelityViolation] {
        let declarations = ArtifactDeclarations(artifact: artifact)
        return declarations.all.flatMap { locationViolations(of: $0) + typeViolations(of: $0) }
            + identityViolations(of: declarations)
    }

    // MARK: - Locations

    func locationViolations(of declaration: LocatedDeclaration) -> [FidelityViolation] {
        guard let location = declaration.location else { return [] }
        guard location.line >= 1, location.line <= text.lineCount else {
            let detail = "line \(location.line) is outside the \(text.lineCount)-line file"
            return [violation(.location, declaration, detail)]
        }
        if let endLine = location.endLine, endLine < location.line {
            return [violation(.location, declaration, "endLine \(endLine) is before line \(location.line)")]
        }
        return columnViolations(of: declaration, at: location) + nameViolations(of: declaration, at: location)
    }

    private func columnViolations(
        of declaration: LocatedDeclaration, at location: SourceLocation
    ) -> [FidelityViolation] {
        let line = text.line(location.line) ?? ""
        guard let character = text.character(line: location.line, column: location.column) else {
            return [violation(
                .location, declaration,
                "column \(location.column) is past the end of line \(location.line) (\(line.count) characters)"
            )]
        }
        guard character.isWhitespace else { return [] }
        return [violation(
            .location, declaration,
            "column \(location.column) is whitespace on line \(location.line): \(line.debugDescription)"
        )]
    }

    private func nameViolations(
        of declaration: LocatedDeclaration, at location: SourceLocation
    ) -> [FidelityViolation] {
        let span = text.span(from: location.line, through: location.endLine ?? location.line)
        guard !WhitespaceInsensitiveSearch(span).matches(of: declaration.name).isEmpty else {
            guard !isSubstituted(declaration, in: span) else { return [] }
            return [violation(
                .location, declaration,
                "the name '\(declaration.name)' does not occur in lines "
                    + "\(location.line)–\(location.endLine ?? location.line)"
            )]
        }
        return []
    }

    /// Accepted only where the language declares the substitution and its keyword is in this span.
    private func isSubstituted(_ declaration: LocatedDeclaration, in span: String) -> Bool {
        difference.substitutedNames.contains { rule in
            guard declaration.name.hasSuffix(rule.suffix) else { return false }
            guard span.range(of: rule.keyword, options: .caseInsensitive) != nil else { return false }
            let stem = String(declaration.name.dropLast(rule.suffix.count))
            return stem.isEmpty || !WhitespaceInsensitiveSearch(span).matches(of: stem).isEmpty
        }
    }

    // MARK: - Identity

    func identityViolations(of declarations: ArtifactDeclarations) -> [FidelityViolation] {
        var seen: Set<String> = []
        return declarations.allTypes.compactMap { type in
            guard !seen.insert(type.id).inserted else { return nil }
            return FidelityViolation(
                rule: .identity,
                declaration: "type \(type.id)",
                detail: "a second type declares the same id"
            )
        }
    }

    // MARK: - Types

    func typeViolations(of declaration: LocatedDeclaration) -> [FidelityViolation] {
        guard let location = declaration.location, location.line >= 1, location.line <= text.lineCount else {
            return []
        }
        let span = text.span(from: location.line, through: location.endLine ?? location.line)
        let search = WhitespaceInsensitiveSearch(span)
        return declaration.spelledTypes.compactMap { spelled in
            typeViolation(of: spelled, in: search, declaration: declaration)
        }
    }

    private func typeViolation(
        of spelled: SpelledType,
        in search: WhitespaceInsensitiveSearch,
        declaration: LocatedDeclaration
    ) -> FidelityViolation? {
        let spelling = TypeSpelling(
            reference: spelled.reference, sugarsGenericCollections: difference.sugarsGenericCollections
        )
        let found = spelling.candidates.lazy
            .map { (candidate: String) in (candidate, self.matches(of: candidate, in: search)) }
            .first { !$0.1.isEmpty }
        guard let (candidate, matches) = found else {
            guard !takesTypeFromField(spelled) else { return nil }
            return violation(
                .type, declaration,
                "\(spelled.role) '\(spelling.preferred)' does not occur in its own source span"
            )
        }
        guard !matches.contains(where: { accepts($0.following, of: spelled.reference) }) else { return nil }
        let following = matches.compactMap { $0.following }.first.map(String.init) ?? "end of span"
        return violation(
            .type, declaration,
            "\(spelled.role) '\(candidate)' is followed by '\(following)' in the source, which continues the type"
        )
    }

    /// Whether the language lets a constructor parameter take an unwritten type from its field.
    private func takesTypeFromField(_ spelled: SpelledType) -> Bool {
        difference.forwardsFieldTypesToConstructorParameters && spelled.mayTakeTypeFromField
    }

    /// Drops a match that is only a longer word's tail, so `Item` is not found inside `LineItem`.
    private func matches(
        of candidate: String, in search: WhitespaceInsensitiveSearch
    ) -> [WhitespaceInsensitiveSearch.Match] {
        let startsWithWord = candidate.first?.continuesIdentifier == true
        return search.matches(of: candidate).filter { !(startsWithWord && $0.isPrecededByWord) }
    }

    /// Whether what follows a matched spelling leaves the type complete.
    private func accepts(_ following: Character?, of reference: TypeReference) -> Bool {
        guard let following else { return true }
        switch following {
        case "?":
            return reference.isOptional
        case "<":
            return !reference.genericArguments.isEmpty
        case "[":
            return reference.isArray || !reference.genericArguments.isEmpty
        default:
            return !following.continuesType || difference.unmodelledTypeSuffixes[following] != nil
        }
    }

    private func violation(
        _ rule: FidelityViolation.Rule, _ declaration: LocatedDeclaration, _ detail: String
    ) -> FidelityViolation {
        FidelityViolation(rule: rule, declaration: declaration.label, detail: detail)
    }
}

extension Character {
    /// Whether this character, written straight after a type, would make the type a different one.
    var continuesType: Bool {
        self == "?" || self == "*" || self == "&" || self == "<" || self == "["
    }
}
