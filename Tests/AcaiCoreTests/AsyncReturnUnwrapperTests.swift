import Testing
@testable import AcaiCore

/// The rule a parser applies to an async member's declared return type, with the wrapper names
/// injected — the engine never knows which language spells asynchrony which way.
@Suite("Async return unwrapping")
struct AsyncReturnUnwrapperTests {
    let unwrapper = AsyncReturnUnwrapper(wrapperNames: ["Promise", "Future"])

    @Test func wrapperWithOneArgumentReportsItsPayload() {
        let payload = unwrapper.unwrapped(
            TypeReference(name: "Promise", genericArguments: [TypeReference(name: "User")]))
        #expect(payload == TypeReference(name: "User"))
    }

    /// The payload keeps its own arguments, so a relationship still points at `Map` and carries
    /// `String`/`User` rather than flattening to the outermost name.
    @Test func nestedGenericPayloadKeepsItsOwnArguments() {
        let inner = TypeReference(
            name: "Map",
            genericArguments: [TypeReference(name: "String"), TypeReference(name: "User")])
        #expect(unwrapper.unwrapped(TypeReference(name: "Future", genericArguments: [inner])) == inner)
    }

    /// The payload's own optionality and arrayness are the payload's, not the wrapper's.
    @Test func payloadKeepsItsOptionalAndArrayFlags() {
        let optional = TypeReference(name: "User", isOptional: true)
        #expect(unwrapper.unwrapped(TypeReference(name: "Future", genericArguments: [optional])) == optional)
        let array = TypeReference(name: "User", isArray: true)
        #expect(unwrapper.unwrapped(TypeReference(name: "Promise", genericArguments: [array])) == array)
    }

    /// `Promise<void>` unwraps like any other payload — there is no separate void rule.
    @Test func voidPayloadIsReportedAsVoid() {
        let unwrapped = unwrapper.unwrapped(
            TypeReference(name: "Promise", genericArguments: [TypeReference(name: "void")]))
        #expect(unwrapped?.name == "void")
    }

    /// A wrapper written without a type argument names no payload, so reporting one would invent a
    /// type the declaration never wrote.
    @Test func bareWrapperIsLeftAsDeclared() {
        let bare = TypeReference(name: "Future")
        #expect(unwrapper.unwrapped(bare) == bare)
    }

    /// An optional or an array *of* the wrapper is not the plain return of an async member, so
    /// unwrapping it would silently drop the `?`/`[]` the declaration does carry.
    @Test func optionalOrArrayOfTheWrapperIsLeftAsDeclared() {
        let optional = TypeReference(
            name: "Future", genericArguments: [TypeReference(name: "User")], isOptional: true)
        #expect(unwrapper.unwrapped(optional) == optional)
        let array = TypeReference(
            name: "Promise", genericArguments: [TypeReference(name: "User")], isArray: true)
        #expect(unwrapper.unwrapped(array) == array)
    }

    @Test func aTypeThatIsNotAWrapperIsLeftAlone() {
        let stream = TypeReference(name: "Stream", genericArguments: [TypeReference(name: "User")])
        #expect(unwrapper.unwrapped(stream) == stream)
    }

    @Test func anAbsentReturnTypeStaysAbsent() {
        #expect(unwrapper.unwrapped(nil) == nil)
    }

    /// Two arguments mean the name is not the single-payload wrapper it looked like, so the
    /// reference is reported as written rather than losing an argument.
    @Test func aWrapperNameCarryingTwoArgumentsIsLeftAlone() {
        let twoArguments = TypeReference(
            name: "Promise",
            genericArguments: [TypeReference(name: "User"), TypeReference(name: "Error")])
        #expect(unwrapper.unwrapped(twoArguments) == twoArguments)
    }
}
