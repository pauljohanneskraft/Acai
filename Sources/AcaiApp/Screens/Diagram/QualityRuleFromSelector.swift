import Foundation
import AcaiQuality

/// Turns a diagram Filter selector into a codebase quality rule: the closest existing rule shape
/// that evaluates a single node against a single bare `Selector` is a `MetricBudget` (every other
/// kind needs two selectors or a relationship edge), so this appends one as an editable scaffold —
/// not a rule guaranteed to fire on every match, since no existing rule kind expresses that.
@MainActor
struct QualityRuleFromSelector {
    let model: ProjectBrowserViewModel
    let codebaseID: UUID

    /// Whether the action can append here: a codebase pointed at an external YAML rules file has
    /// nothing in this app to append to (the app only form-edits its own managed rules).
    var isAvailable: Bool {
        let path = model.codebase(for: codebaseID)?.qualityCheck?.rulesPath ?? ""
        return path.isEmpty || model.store.isManaged(path: path)
    }

    /// Appends `selector` as a metric-budget scaffold to the codebase's managed quality rules.
    func appendRule(for selector: AcaiQuality.Selector) {
        var rules = model.editing.loadEditableRules(codebaseID: codebaseID)
        rules.budgets.append(MetricBudget(target: selector, metric: .maxCyclomaticComplexity, max: 10))
        model.editing.saveAuthoredRules(codebaseID: codebaseID, rules: rules)
    }
}
