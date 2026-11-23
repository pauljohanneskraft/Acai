import Testing
@testable import AcaiCore

@Suite("Async return unwrapping")
struct AsyncReturnUnwrapperTests {
    let unwrapper = AsyncReturnUnwrapper(wrapperNames: ["Promise", "Future"])

    @Test func wrapperWithOneArgumentReportsItsPayload() {
        let payload = unwrapper.unwrapped(
            TypeReference(name: "Promise", genericArguments: [TypeReference(name: "User")]))
        #expect(payload == TypeReference(name: "User"))
    }

    @Test func nestedGenericPayloadKeepsItsOwnArguments() {
        let inner = TypeReference(
            name: "Map",
            genericArguments: [TypeReference(name: "String"), TypeReference(name: "User")])
        #expect(unwrapper.unwrapped(TypeReference(name: "Future", genericArguments: [inner])) == inner)
    }

    @Test func payloadKeepsItsOptionalAndArrayFlags() {
        let optional = TypeReference(name: "User", isOptional: true)
        #expect(unwrapper.unwrapped(TypeReference(name: "Future", genericArguments: [optional])) == optional)
        let array = TypeReference(name: "User", isArray: true)
        #expect(unwrapper.unwrapped(TypeReference(name: "Promise", genericArguments: [array])) == array)
    }

    @Test func voidPayloadIsReportedAsVoid() {
        let unwrapped = unwrapper.unwrapped(
            TypeReference(name: "Promise", genericArguments: [TypeReference(name: "void")]))
        #expect(unwrapped?.name == "void")
    }

    @Test func bareWrapperIsLeftAsDeclared() {
        let bare = TypeReference(name: "Future")
        #expect(unwrapper.unwrapped(bare) == bare)
    }

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

    @Test func aWrapperNameCarryingTwoArgumentsIsLeftAlone() {
        let twoArguments = TypeReference(
            name: "Promise",
            genericArguments: [TypeReference(name: "User"), TypeReference(name: "Error")])
        #expect(unwrapper.unwrapped(twoArguments) == twoArguments)
    }
}
