import SwiftUI
import WidgetKit

@main
struct GrandmaWantsPicsWidgetBundle: WidgetBundle {
    var body: some Widget {
        GrandmaWantsPicsWidget()
    }
}

struct GrandmaWantsPicsWidget: Widget {
    let kind = "GrandmaWantsPicsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GrandmaWantsPicsWidgetProvider()) { entry in
            GrandmaWantsPicsWidgetView(entry: entry)
        }
        .configurationDisplayName("GrandmaWantsPics")
        .description("See when Grandma last got photos or if requests are waiting.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
