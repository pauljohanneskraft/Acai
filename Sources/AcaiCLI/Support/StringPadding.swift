extension String {
    /// Pads with trailing spaces to at least `width` characters (left-aligned).
    func paddedTrailing(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }

    /// Pads with leading spaces to at least `width` characters (right-aligned).
    func paddedLeading(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
