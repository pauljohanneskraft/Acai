extension String {
    func paddedTrailing(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }

    func paddedLeading(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
