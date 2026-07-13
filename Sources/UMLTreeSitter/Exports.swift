@_exported import SwiftTreeSitter

// Re-exported so every language plugin target — which only depends on `UMLTreeSitter`, not
// `SwiftTreeSitter` directly — can reference `Node`/`Language`/`Query`/… with a single
// `import UMLTreeSitter`.
