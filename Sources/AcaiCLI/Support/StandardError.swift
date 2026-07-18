import Foundation

extension String {
    /// Writes the string followed by a newline to standard error. Warnings go here so they don't
    /// interleave with piped stdout (DOT / Mermaid / JSON), which would corrupt a redirected file.
    func writeLineToStandardError() {
        FileHandle.standardError.write(Data((self + "\n").utf8))
    }
}
