/// Response For a Class (RFC): the size of a type's response set — the methods it declares plus the
/// distinct methods it can invoke. High RFC means a lot can happen in reaction to a message to the
/// type, which raises testing and comprehension cost.
///
/// Approximated from already-parsed data: the weighted-method count (methods the type declares) plus
/// the number of *distinct* call targets (`receiver` + `method` name) observed across the type's member
/// bodies. Dynamic dispatch the parser can't resolve is simply absent, so this is a lower bound.
struct ResponseForClass {
    let type: TypeDeclaration

    init(type: TypeDeclaration) {
        self.type = type
    }

    var count: Int {
        let methods = type.members.filter { $0.kind == .method }.count
        var targets: Set<String> = []
        for member in type.members {
            for call in member.callSites {
                // NUL-separated so distinct (receiver, method) pairs never collide.
                targets.insert("\(call.receiverType ?? "")\u{0}\(call.methodName)")
            }
        }
        return methods + targets.count
    }
}
