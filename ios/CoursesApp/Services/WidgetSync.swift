import Foundation
import WidgetKit

/// Тримає віджет у курсі справ. Викликається щоразу, коли застосунок дізнався
/// свіжий розклад — віджет сам у мережу не ходить.
enum WidgetSync {
    static func update(nextSession item: ScheduleItem?) {
        let shared = item.flatMap { item -> SharedSession? in
            guard let start = Fmt.date(item.session.startAt) else { return nil }
            return SharedSession(
                title: item.session.title,
                courseTitle: item.courseTitle,
                startAt: start,
                joinURL: item.session.joinURL)
        }
        SharedSchedule.save(shared)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
