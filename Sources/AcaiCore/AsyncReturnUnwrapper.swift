/// Reports an async member's payload in place of the wrapper type its language makes it name.
public struct AsyncReturnUnwrapper: Sendable, Equatable, Hashable {
    public let wrapperNames: Set<String>

    public init(wrapperNames: Set<String>) {
        self.wrapperNames = wrapperNames
    }

    /// `reference` unchanged unless it is a non-optional, non-array wrapper with exactly one argument.
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
