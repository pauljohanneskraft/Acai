import Foundation

/// The format specifiers of a printf-style string, keyed by the argument position each one consumes.
/// A catalog key and its translations are only comparable in this form: `Depth %lld` and `Tiefe: %@`
/// have the same placeholder *count*, and formatting an `Int64` through `%@` reads it as a pointer.
struct FormatArguments: Equatable, CustomStringConvertible {
    let byPosition: [Int: String]

    /// `%` characters that are neither a specifier nor an escaped `%%`. The formatter swallows one,
    /// so `"%lld%"` renders "120" where "120%" was meant.
    let strayPercents: Int

    /// `substitutions` is the localization's `substitutions` block, which resolves each `%#@name@`
    /// to the argument it stands for.
    init(_ format: String, substitutions: [String: [String: Any]] = [:]) {
        let specifier = /%(?:%|(?:(\d+)\$)?(?:#@(\w+)@|[-+ 0#']*[\d.]*((?:hh|h|ll|l|q|z|t|j|L)?)([@a-zA-Z])))/
        var byPosition: [Int: String] = [:]
        var next = 1
        var accounted = 0
        for match in format.matches(of: specifier) {
            let (whole, position, substitution, length, conversion) = match.output
            accounted += whole == "%%" ? 2 : 1
            guard whole != "%%" else { continue }
            if let substitution {
                guard let entry = substitutions[String(substitution)],
                      let argument = entry["argNum"] as? Int,
                      let specifier = entry["formatSpecifier"] as? String else { continue }
                byPosition[argument] = specifier
                next = max(next, argument + 1)
                continue
            }
            guard let length, let conversion else { continue }
            let argument = position.flatMap { Int($0) } ?? next
            byPosition[argument] = String(length) + String(conversion)
            next = max(next, argument + 1)
        }
        self.byPosition = byPosition
        self.strayPercents = format.count(where: { $0 == "%" }) - accounted
    }

    var description: String {
        byPosition.sorted { $0.key < $1.key }.map { "\($0.key):%\($0.value)" }.joined(separator: " ")
    }
}
