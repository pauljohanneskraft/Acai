import Foundation

/// A decoded JSON tree the equivalence suite can rewrite and compare.
///
/// The suite compares whole `CodeArtifact`s rather than `ContractShape`s, so a field the projection
/// has never heard of — a modifier, a call site, an end line — still has to survive a variation. A
/// tree walk is exhaustive by construction, which a hand-written traversal of the model would stop
/// being the next time a field is added.
indirect enum ContractJSON: Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([ContractJSON])
    case object([String: ContractJSON])

    init(jsonObject: Any) {
        switch jsonObject {
        case let dictionary as [String: Any]:
            self = .object(dictionary.mapValues { ContractJSON(jsonObject: $0) })
        case let array as [Any]:
            self = .array(array.map { ContractJSON(jsonObject: $0) })
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            self = CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .number(number.doubleValue)
        case let bool as Bool:
            self = .bool(bool)
        default:
            self = .null
        }
    }

    /// Key order fixed and indentation dropped, so two trees sort and print the same way.
    var canonicalText: String {
        switch self {
        case .null:
            return "null"
        case .bool(let value):
            return value ? "true" : "false"
        case .number(let value):
            return value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : String(value)
        case .string(let value):
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        case .array(let elements):
            return "[\(elements.map(\.canonicalText).joined(separator: ","))]"
        case .object(let fields):
            let pairs = fields.keys.sorted().map { "\"\($0)\":\(fields[$0]!.canonicalText)" }
            return "{\(pairs.joined(separator: ","))}"
        }
    }
}
