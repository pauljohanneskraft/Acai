/// The subset of TOML shapes the layout keys in `pyproject.toml` need: strings, arrays, and tables.
/// Numbers, booleans and dates are kept verbatim as ``scalar`` — nothing here reads them, so
/// interpreting them would only add ways to reject a file that is actually valid.
enum TOMLValue: Equatable, Sendable {
    case string(String)
    case scalar(String)
    case array([TOMLValue])
    case table([String: TOMLValue])
}

extension TOMLValue {
    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var arrayValue: [TOMLValue]? {
        guard case .array(let values) = self else { return nil }
        return values
    }

    var tableValue: [String: TOMLValue]? {
        guard case .table(let table) = self else { return nil }
        return table
    }

    /// The value at a dotted path through tables, e.g. `["tool", "poetry", "packages"]`. An array
    /// only ever ends a path: which of its elements a further key would mean is ambiguous.
    func value(at path: [String]) -> TOMLValue? {
        var current = self
        for key in path {
            guard let next = current.tableValue?[key] else { return nil }
            current = next
        }
        return current
    }
}
