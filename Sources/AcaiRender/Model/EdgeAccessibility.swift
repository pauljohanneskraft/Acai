import SwiftUI

/// What an edge tells VoiceOver, already localized by the app — this module carries no strings.
/// One phrase, not a label plus a value: an edge is drawn, not a control, and AppKit exposes no
/// accessibility value for a plain element, so anything kept out of the label goes unspoken on macOS.
public struct EdgeAccessibility: Equatable, Sendable {
    public struct RotorEntry: Equatable, Sendable {
        public let id: String
        public let namespace: Namespace.ID

        public init(id: String, namespace: Namespace.ID) {
            self.id = id
            self.namespace = namespace
        }
    }

    public let label: String
    public let identifier: String?
    public let sortPriority: Double
    public let rotorEntry: RotorEntry?

    public init(label: String, identifier: String? = nil, sortPriority: Double = 0, rotorEntry: RotorEntry? = nil) {
        self.label = label
        self.identifier = identifier
        self.sortPriority = sortPriority
        self.rotorEntry = rotorEntry
    }
}
