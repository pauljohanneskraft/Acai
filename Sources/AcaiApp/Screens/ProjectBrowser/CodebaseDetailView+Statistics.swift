import SwiftUI
import AcaiCore

extension CodebaseDetailView {

    func typeDetail(
        _ title: LocalizedStringResource, _ description: LocalizedStringResource,
        _ types: [CodeMetrics.TypeMetric],
        by keyPath: KeyPath<CodeMetrics.TypeMetric, Int>
    ) -> StatisticDetail {
        StatisticDetailBuilder(artifact: artifact).typeDetail(title, description, types, by: keyPath)
    }

    func typeDetail(
        _ title: LocalizedStringResource, _ description: LocalizedStringResource,
        _ types: [CodeMetrics.TypeMetric],
        by keyPath: KeyPath<CodeMetrics.TypeMetric, Double>, format: (Double) -> String
    ) -> StatisticDetail {
        StatisticDetailBuilder(artifact: artifact).typeDetail(title, description, types, by: keyPath, format: format)
    }

    func moduleDetail(
        _ title: LocalizedStringResource, _ description: LocalizedStringResource,
        _ modules: [CodeMetrics.ModuleCoupling],
        value: (CodeMetrics.ModuleCoupling) -> Double, format: (Double) -> String
    ) -> StatisticDetail {
        StatisticDetailBuilder(artifact: artifact)
            .moduleDetail(title, description, modules, value: value, format: format)
    }
}
