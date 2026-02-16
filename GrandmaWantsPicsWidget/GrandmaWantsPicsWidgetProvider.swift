import WidgetKit
import Foundation

struct GrandmaWantsPicsWidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> GrandmaWantsPicsWidgetEntry {
        GrandmaWantsPicsWidgetEntry(date: .now, widgetData: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (GrandmaWantsPicsWidgetEntry) -> Void) {
        completion(GrandmaWantsPicsWidgetEntry(date: .now, widgetData: loadData()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GrandmaWantsPicsWidgetEntry>) -> Void) {
        let data = loadData()
        let now = Date()

        // Create entries at 30-minute intervals for 4 hours so "time since" stays current.
        // The main app also calls WidgetCenter.shared.reloadAllTimelines() on data changes.
        var entries: [GrandmaWantsPicsWidgetEntry] = []
        for minuteOffset in stride(from: 0, through: 240, by: 30) {
            let entryDate = Calendar.current.date(byAdding: .minute, value: minuteOffset, to: now)!
            entries.append(GrandmaWantsPicsWidgetEntry(date: entryDate, widgetData: data))
        }

        let timeline = Timeline(entries: entries, policy: .after(
            Calendar.current.date(byAdding: .hour, value: 4, to: now)!
        ))
        completion(timeline)
    }

    private func loadData() -> WidgetData {
        guard let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName),
              let jsonData = defaults.data(forKey: AppGroupConstants.widgetDataKey),
              let widgetData = try? JSONDecoder().decode(WidgetData.self, from: jsonData)
        else {
            return .empty
        }
        return widgetData
    }
}
