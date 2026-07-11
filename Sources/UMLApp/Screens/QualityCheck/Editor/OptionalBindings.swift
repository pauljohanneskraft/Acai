import SwiftUI

extension Binding where Value == String? {
    /// Presents an optional string as a plain text binding: an empty field reads back as `nil`, so an
    /// untouched form facet stays absent rather than becoming an empty-string predicate.
    var orEmpty: Binding<String> {
        Binding<String>(
            get: { wrappedValue ?? "" },
            set: { wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
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
