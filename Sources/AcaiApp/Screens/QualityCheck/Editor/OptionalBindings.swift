import SwiftUI

extension Binding {
    /// Presents an optional value as a plain binding: reading back `value` clears the wrapped
    /// optional, so an untouched form facet stays absent rather than becoming an explicit predicate.
    func or<Wrapped: Equatable>(default value: Wrapped) -> Binding<Wrapped> where Value == Wrapped? {
        Binding<Wrapped>(
            get: { wrappedValue ?? value },
            set: { wrappedValue = $0 == value ? nil : $0 }
        )
    }
}

extension Binding where Value == String? {
    var orEmpty: Binding<String> { or(default: "") }
}

extension Binding where Value == Double? {
    /// Presents an optional number as a text binding: blank/invalid input reads back as `nil` (no
    /// bound), any parseable number becomes the value.
    var asText: Binding<String> {
        Binding<String>(
            get: { wrappedValue.map { String($0) } ?? "" },
            set: { wrappedValue = Double($0) }
        )
    }
}

extension Binding where Value == Int? {
    /// Presents an optional integer as a text binding: blank/invalid input reads back as `nil` (facet
    /// stays unset), any parseable integer becomes the value.
    var asText: Binding<String> {
        Binding<String>(
            get: { wrappedValue.map { String($0) } ?? "" },
            set: { wrappedValue = Int($0) }
        )
    }
}
