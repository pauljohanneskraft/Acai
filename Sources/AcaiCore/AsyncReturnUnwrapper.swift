/// Erases the wrapper type a language forces an asynchronous member to name, so the member reports
/// the payload a language that marks asynchrony with a keyword alone reports.
///
/// Language-agnostic: the wrapper names are injected by the parser that knows them, exactly as
/// ``LanguageConfiguration``'s reference data is. Applied only where the parser has already recorded
/// ``Modifier/async``; a wrapper named by a member that is *not* asynchronous is a real return type
/// and is left alone.
public struct AsyncReturnUnwrapper: Sendable, Equatable, Hashable {
    /// The simple names of the language's asynchronous-return wrappers, e.g. `["Promise"]`.
    public let wrapperNames: Set<String>

    public init(wrapperNames: Set<String>) {
        self.wrapperNames = wrapperNames
    }

    /// The payload of a wrapped reference, or `reference` unchanged when there is no single payload
    /// to report: a wrapper written without a type argument names none, and an optional or an array
    /// *of* the wrapper is not the plain return of an asynchronous member. Unwrapping those would
    /// report a type the declaration never wrote.
    public func unwrapped(_ reference: TypeReference?) -> TypeReference? {
        guard let reference,
              wrapperNames.contains(reference.name),
              !reference.isOptional,
              !reference.isArray,
              reference.genericArguments.count == 1
        else { return reference }
        return reference.genericArguments[0]
    }
}
