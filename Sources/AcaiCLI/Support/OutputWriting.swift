import Foundation

extension String {
    func writeOutput(to path: String?, label: String) throws {
        guard let path else {
            print(self)
            return
        }
        try write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        print("Wrote \(label) to \(path)")
    }
}
