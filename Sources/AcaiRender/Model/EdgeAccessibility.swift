import Foundation

/// What an edge tells VoiceOver, already localized by the app — this module carries no strings.
public struct EdgeAccessibility: Equatable, Sendable {
    public let label: String
    public let value: String
    public let identifier: String?

    public init(label: String, value: String, identifier: String? = nil) {
        self.label = label
        self.value = value
        self.identifier = identifier
    }
}
