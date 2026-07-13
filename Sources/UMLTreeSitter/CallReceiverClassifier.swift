import UMLCore

/// The head of a call/access chain, already peeled from raw nodes by `MemberBodyWalker` using only
/// `TreeSitterExpressionGrammar` — this type carries no grammar dependency, which is what lets one
/// classifier serve every language.
enum ReceiverHeadKind: Sendable {
    case selfKeyword
    case identifier(String)
}

/// Decides every `CallReceiver` case in exactly one place, for every language — this is where the
/// historical "fix it once per language" problem is structurally closed. Mirrors the current,
/// intentionally conservative behavior: an unresolvable receiver returns `nil` (the call site is
/// dropped entirely, never tagged `.unknown`), and a property/member chain is only resolved one hop
/// deep — deeper chains are left unresolved rather than guessed.
struct CallReceiverClassifier: Sendable {

    /// Classifies a call reached through an explicit receiver chain: `head` is the innermost
    /// expression, `hops` are the member names accessed after it, in order (empty for a direct
    /// `head.method()`; a `self.prop.method()` call has one `hop`).
    func classify(head: ReceiverHeadKind, hops: [String], index: KnownMemberIndex) -> CallReceiver? {
        switch (head, hops.count) {
        case (.selfKeyword, 0):
            return .selfDispatch
        case (.selfKeyword, 1):
            return resolvedIdentifier(hops[0], index: index)
        case (.identifier(let name), 0):
            return resolvedIdentifier(name, index: index)
        case (.identifier(let name), 1):
            guard let headType = index.knownProperties[name] ?? (index.knownTypeNames.contains(name) ? name : nil)
            else { return nil }
            return .propertyChain(headTypeName: headType, hops: hops)
        default:
            // Deeper chains (2+ hops through either `self` or a named receiver) aren't provably
            // resolvable from a single file's information alone — dropped, matching current behavior.
            return nil
        }
    }

    /// Classifies a bare call with no explicit receiver (`foo()`). `nil` when `name` is a known
    /// type — that's a construction (`Foo()`), not a call.
    func classifyBareCall(named name: String, implicitSelf: Bool, index: KnownMemberIndex) -> CallReceiver? {
        guard !index.knownTypeNames.contains(name) else { return nil }
        return implicitSelf ? .selfDispatch : .free
    }

    /// A single-identifier receiver (`receiver.method()`): a typed stored property resolves to its
    /// declared type; a name matching a known type is a static `TypeName.method()` call; a
    /// capitalized name matching neither is deferred (`.unresolvedTypeName`) — possibly a type
    /// declared elsewhere in the project, resolved post-merge by
    /// `CodeArtifact.resolvingCallSiteReceivers()`. Anything else (locals, parameters with no known
    /// type, lowercase external receivers) returns `nil`.
    private func resolvedIdentifier(_ name: String, index: KnownMemberIndex) -> CallReceiver? {
        if let type = index.knownProperties[name] {
            return .type(type)
        }
        if index.knownTypeNames.contains(name) {
            return .type(name)
        }
        if name.first?.isUppercase == true {
            return .unresolvedTypeName(name)
        }
        return nil
    }
}
