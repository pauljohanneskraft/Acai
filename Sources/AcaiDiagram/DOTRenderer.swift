/// Cosmetic rendering knobs shared by every diagram renderer: the optional colour
/// `theme` plus the Graphviz `fontName`/`fontSize`. Replaces the loose
/// `(theme:fontName:fontSize:)` parameter trio the individual renderers used to carry.
public struct DiagramRenderOptions: Sendable {
    /// The colour palette. `nil` emits structural output (no background/fill/border/font
    /// colours) so the consumer themes it at render time.
    public var theme: DiagramTheme?
    public var fontName: String
    public var fontSize: Int

    public init(
        theme: DiagramTheme? = nil,
        fontName: String = "Helvetica",
        fontSize: Int = 12
    ) {
        self.theme = theme
        self.fontName = fontName
        self.fontSize = fontSize
    }
}

/// Shared behaviour for the Graphviz-DOT renderers. Conformers expose their
/// `DiagramRenderOptions`; in return they get the font/theme accessors and a single
/// `graphAttributes(rankdir:compound:nodeDefaults:)` helper, replacing the near-identical
/// `graphAttributes()` each renderer used to re-declare (they differed only in `rankdir`,
/// an optional `compound=true;` line, and the node-default prefix).
public protocol DOTRenderer: Sendable {
    var renderOptions: DiagramRenderOptions { get }
}

extension DOTRenderer {
    public var theme: DiagramTheme? { renderOptions.theme }
    public var fontName: String { renderOptions.fontName }
    public var fontSize: Int { renderOptions.fontSize }

    /// The graph-level DOT preamble common to every diagram type.
    ///
    /// - Parameters:
    ///   - rankdir: the `rankdir` value (`TB`, `LR`, …).
    ///   - compound: when `true`, emits a `compound=true;` line (needed for cluster edges).
    ///   - nodeDefaults: attributes prepended inside the default `node [...]` list (e.g.
    ///     `"shape=none margin=0 "`); must include its own trailing space when non-empty.
    public func graphAttributes(
        rankdir: String,
        compound: Bool = false,
        nodeDefaults: String = ""
    ) -> String {
        let background = theme.map { "  bgcolor=\"\($0.backgroundColor)\";\n" } ?? ""
        let compoundLine = compound ? "  compound=true;\n" : ""
        return """
          rankdir=\(rankdir);
        \(background)\(compoundLine)  fontname="\(fontName)";
          fontsize=\(fontSize);
          node [\(nodeDefaults)fontname="\(fontName)" fontsize=\(fontSize)];
          edge [fontname="\(fontName)" fontsize=\(fontSize - 2)];

        """
    }
}
