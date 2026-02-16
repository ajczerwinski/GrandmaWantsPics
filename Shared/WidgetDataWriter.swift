import Foundation
import WidgetKit

enum WidgetDataWriter {

    static func write(_ data: WidgetData) {
        guard let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName) else { return }
        if let encoded = try? JSONEncoder().encode(data) {
            defaults.set(encoded, forKey: AppGroupConstants.widgetDataKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
