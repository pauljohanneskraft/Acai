import Foundation

extension String {
    /// Warnings go here so they don't interleave with piped stdout (DOT / Mermaid / JSON), which
    /// would corrupt a redirected file.
    func writeLineToStandardError() {
        FileHandle.standardError.write(Data((self + "\n").utf8))
    }
}
