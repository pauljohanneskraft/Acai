import SwiftUI

// Explanatory copy for the statistics cards, kept out of `CodebaseDetailView.swift` so it stays within
// SwiftLint's `file_length`. Each blurb reads in the card's detail sheet.
extension CodebaseDetailView {

    static let instabilityBlurb =
        "I = Ce / (Ca + Ce): how exposed a module is to change from its dependencies. "
        + "0% = stable (depended upon, depends on little); 100% = unstable (depends outward, nothing "
        + "depends on it). Neither is inherently bad — foundational modules should be stable, leaf/app "
        + "modules unstable."
    static let inheritanceDepthBlurb =
        "Longest inheritance/conformance chain for a type. 0–2 is easy to follow; deep chains (>5) are "
        + "a complexity smell."
    static let fanOutBlurb =
        "How many other types this type depends on. High fan-out means many responsibilities — harder "
        + "to change and test, and a candidate for splitting."
    static let fanInBlurb =
        "How many types depend on this type. High fan-in marks a core/hub type; expected for shared "
        + "models, but keep them stable and well-tested since changes ripple widely."
    static let weightedMethodsBlurb =
        "Weighted methods per type (method count). Large types carry many responsibilities (low "
        + "cohesion / SRP risk) and are prime candidates for splitting."
    static let responseForClassBlurb =
        "Response For a Class: the methods a type declares plus the distinct methods it calls. A large "
        + "response set means a lot can happen in reaction to one message — costly to test and reason about."
    static let publicSurfaceBlurb =
        "Share of a type's members that are public/open — its outward API surface. A wide surface on a "
        + "big type leaks internals and makes the type hard to change without breaking callers."
    static let mutablePublicStateBlurb =
        "Publicly settable stored properties. Mutable public state breaks encapsulation: any caller can "
        + "change the type's internals directly. Prefer read-only exposure with narrowed setters."
    static let parametersBlurb =
        "Widest parameter list among a type's methods/initializers. Long parameter lists are hard to call "
        + "correctly and often signal a missing type that should bundle the arguments."
    static let dataClassScoreBlurb =
        "Share of a type that is data rather than behaviour (properties ÷ properties + methods). A type "
        + "that is nearly all data, reached into from elsewhere, is an anemic domain model."
    static let nestingDepthBlurb =
        "Depth of a type's nested-type tree. Deeply nested types are harder to name, find, and reason "
        + "about; consider promoting them to the top level."
    static let overrideCountBlurb =
        "Members that override an inherited one. Many overrides can be a refused-bequest signal — the "
        + "subclass rejecting much of what it inherits, hinting it isn't truly a subtype."
    static let deepAndWideBlurb =
        "Deep-and-wide inheritance shape (depth × children). A type both deeply derived and widely "
        + "subclassed sits at a fragile hierarchy hub where changes ripple in every direction."
    static let lackOfCohesionBlurb =
        "LCOM4 cohesion: how many disconnected groups the type's methods fall into once linked by shared "
        + "fields or calls. 1 is cohesive; higher means several unrelated jobs that want separate types."
    static let featureEnvyBlurb =
        "Methods more interested in another type than their own — they call into a neighbour more than "
        + "themselves. Feature envy hints the behaviour belongs on the type it keeps reaching into."
}
