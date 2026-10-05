import SwiftUI
import WidgetKit

/// A codebase's state as of its last analysis. Tapping it opens that codebase (`widgetURL`),
/// not the app's front door.
public struct CodebaseStateWidget: Widget {
    public static let kind = "CodebaseStateWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: SelectCodebaseIntent.self,
            provider: CodebaseStateProvider()
        ) { entry in
            CodebaseStateWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Text(.widget("Widget.CodebaseState.DisplayName")))
        .description(Text(.widget("Widget.CodebaseState.Description")))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
