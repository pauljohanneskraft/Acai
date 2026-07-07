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
    static let abstractnessBlurb =
        "A = abstract types / total types in a module (interfaces, protocols, abstract classes). High "
        + "abstractness suits a stable, foundational module; a concrete module heavily depended upon is "
        + "rigid. Paired with instability via the distance-from-main-sequence metric."
    static let distanceBlurb =
        "D = |A + I − 1|: how far a module sits from Martin's ideal balance of abstractness and "
        + "stability. 0% is on the main sequence; high values flag the 'zone of pain' (concrete + "
        + "stable, rigid) or the 'zone of uselessness' (abstract + unstable, unused)."
    static let sdpBlurb =
        "Stable-Dependencies-Principle breaches: modules this one depends on that are *less* stable than "
        + "it — a dependency on something likelier to change than you, so edits ripple up. Not a cycle, "
        + "so cycle detection misses it. Tap for the offending modules."
    static let cyclomaticComplexityBlurb =
        "The highest cyclomatic complexity of any single method: 1 + its decision points (branches, "
        + "loops, switch cases, catches), counted at every nesting depth. Surfaces the one gnarly method "
        + "that a plain method count hides — a prime target to extract and test."
    static let numberOfPropertiesBlurb =
        "Stored/computed properties on a type — the data half of the anemic-vs-behaviour balance. A type "
        + "that is mostly fields with little behaviour is a data class other code reaches into."
    static let numberOfChildrenBlurb =
        "Direct subtypes/conformers in the codebase. A widely-subclassed type is a hierarchy hub: changes "
        + "to it ripple to every child, so keep its contract stable."
    static let efferentBlurb =
        "Efferent coupling (Ce): how many types outside the module it depends on. High Ce means the "
        + "module reaches broadly outward — sensitive to changes elsewhere and harder to reuse in isolation."
    static let afferentBlurb =
        "Afferent coupling (Ca): how many types outside the module depend on it. High Ca marks a "
        + "foundational module many others rely on — keep it stable, since changes ripple widely."
}
