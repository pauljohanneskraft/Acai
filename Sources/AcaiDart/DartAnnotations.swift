import AcaiCore
import AcaiTreeSitter

/// Reads Dart `annotation` nodes (`@override`, `@Deprecated('msg')`) and applies them to the
/// members they precede. Stateless beyond `context`.
struct DartAnnotations {
    let context: SourceFileContext

    /// The annotations among a node's direct children.
    func annotations(of node: Node) -> [String] {
        node.children().compactMap { $0.nodeType == "annotation" ? text($0) : nil }
    }

    /// An `annotation` node's full source text (incl. the leading `@` and any arguments),
    /// matching how the Kotlin and Java extractors store annotations — preserving argument
    /// detail like `@Deprecated('reason')` rather than discarding it.
    func text(_ node: Node) -> String {
        node.text(in: context)
    }

    /// Applies the collected annotations to every member added since `startIndex` (a single
    /// declaration like `@override int a, b;` yields multiple fields that share the annotation).
    func assign(_ annotations: [String], toMembersFrom startIndex: Int, in members: inout [Member]) {
        guard !annotations.isEmpty, startIndex < members.count else { return }
        // `@override` maps to the `.override` modifier, so the dead-code scan exempts it.
        let isOverride = annotations.contains { annotation in
            let name = annotation.hasPrefix("@") ? String(annotation.dropFirst()) : annotation
            return name.lowercased() == "override"
        }
        for index in startIndex..<members.count {
            members[index].annotations = annotations
            if isOverride, !members[index].modifiers.contains(.override) {
                members[index].modifiers.append(.override)
            }
        }
    }
}
