import Foundation

/// What an edge tells VoiceOver, already localized by the app — this module carries no strings.
/// One phrase, not a label plus a value: an edge is drawn, not a control, and AppKit exposes no
/// accessibility value for a plain element, so anything kept out of the label goes unspoken on macOS.
public struct EdgeAccessibility: Equatable, Sendable {
    public let label: String
    public let identifier: String?

    public init(label: String, identifier: String? = nil) {
        self.label = label
        self.identifier = identifier
    }
}
