import AcaiCore

/// Per-function-body call-site-collection state: the property/parameter/local maps a call-site
/// receiver resolves against, and the buffers a body's calls/assignments/field-reads accumulate into
/// before folding into its `Member`. Grouped into one value so resetting it (new top-of-body
/// function/initializer, or once finalized) is a single assignment.
struct CallSiteAccumulator {
    var pendingCallSites: [CallSite] = []
    var pendingAssignments: [VariableAssignment] = []
    var pendingFieldReads: [FieldAccess] = []
    var propertyMap: [String: String] = [:]
    /// Separate from `propertyMap`: an array's element is only a valid receiver inside an iteration
    /// closure's implicit `$0`, never a direct call on the property itself.
    var arrayElementPropertyMap: [String: String] = [:]
    var localMap: [String: String] = [:]
    /// A binding whose type couldn't be proven concretely in this file but is resolvable post-merge.
    /// Consulted only after `localMap` misses.
    var localReceiverOriginMap: [String: CallReceiver] = [:]
    var parameterMap: [String: String] = [:]
    /// Every local/parameter name declared so far, whether or not its type was provable — unlike
    /// `localMap`/`parameterMap`. Consulted so a local whose type inference failed isn't mistaken for
    /// an unresolved own-property receiver: both look identical (a lowercase name, no map entry).
    var knownLocalNames: Set<String> = []
}
