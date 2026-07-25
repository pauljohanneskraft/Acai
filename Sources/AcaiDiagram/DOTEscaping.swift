import Foundation

extension String {
    /// Wraps the string in DOT double-quotes, escaping any internal quotes.
    var dotNodeID: String {
        "\"" + replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// For use inside a DOT quoted string.
    var dotEscaped: String {
        self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// For use inside a DOT HTML label.
    var dotHTMLEscaped: String {
        self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
