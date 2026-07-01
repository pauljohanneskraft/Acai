/// An ordered set of architectural layers (top → bottom). Dependencies may only flow *downward*;
/// an edge from a lower layer up to a higher one is a violation. With `allowSkip == false` a layer
/// may depend only on the layer immediately beneath it. Types matching no layer are unconstrained.
public struct LayerRule: Codable, Equatable, Sendable {
    public struct Layer: Codable, Equatable, Sendable {
        public var name: String
        public var selector: Selector

        public init(name: String, selector: Selector) {
            self.name = name
            self.selector = selector
        }
    }

    /// Layers from top (index 0) to bottom; lower index = higher level.
    public var layers: [Layer]
    /// When `false`, a layer may depend only on the immediately adjacent lower layer.
    public var allowSkip: Bool

    public init(layers: [Layer], allowSkip: Bool = true) {
        self.layers = layers
        self.allowSkip = allowSkip
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        layers = try container.decode([Layer].self, forKey: .layers)
        allowSkip = try container.decodeIfPresent(Bool.self, forKey: .allowSkip) ?? true
    }
}
