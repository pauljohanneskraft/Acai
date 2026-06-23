import Foundation

extension String {
    /// Writes the string to `path` (announcing `Wrote <label> to <path>` on stdout), or prints it to
    /// stdout when `path` is `nil`. Centralizes the file-or-stdout output pattern shared by the
    /// text-producing commands (`analyze`, `diagram`, `metrics`).
    func writeOutput(to path: String?, label: String) throws {
        guard let path else {
            print(self)
            return
        }
        try write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        print("Wrote \(label) to \(path)")
    }
}
