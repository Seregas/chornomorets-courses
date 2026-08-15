import SwiftUI
import WidgetKit

struct NextSessionEntry: TimelineEntry {
    let date: Date
    let session: SharedSession?
}

/// Дані бере з App Group — застосунок кладе туди зріз при кожному оновленні
/// розкладу. Віджет не ходить у мережу: він має малюватися миттєво й офлайн.
struct NextSessionProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextSessionEntry {
        NextSessionEntry(date: Date(), session: SharedSession(
            title: "Заняття 1", courseTitle: "Стрес, втома і піклування про себе",
            startAt: Date().addingTimeInterval(3600), joinURL: nil))
    }

    func getSnapshot(in context: Context, completion: @escaping (NextSessionEntry) -> Void) {
        completion(NextSessionEntry(date: Date(), session: SharedSchedule.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextSessionEntry>) -> Void) {
        let session = SharedSchedule.load()
        let entry = NextSessionEntry(date: Date(), session: session)
        // Перемальовуємо, коли заняття почалося (щоб зникло) або раз на годину.
        let next = session.map { $0.startAt.addingTimeInterval(60) } ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(max(next, Date().addingTimeInterval(300)))))
    }
}

struct NextSessionWidgetView: View {
    var entry: NextSessionEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let session = entry.session {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.startAt, style: .relative)
                    .font(.caption2).foregroundStyle(.secondary)
                Text(session.title)
                    .font(.headline).lineLimit(1)
                Text(session.courseTitle)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(family == .systemSmall ? 2 : 1)
                Spacer(minLength: 0)
                Text(session.startAt, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.widgetAccent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "graduationcap").foregroundStyle(Color.widgetAccent)
                Text("Немає запланованих занять")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

extension Color {
    /// Той самий морський акцент, що й у застосунку (#0E7C86).
    static let widgetAccent = Color(red: 0.055, green: 0.486, blue: 0.525)
}

struct NextSessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextSessionWidget", provider: NextSessionProvider()) { entry in
            NextSessionWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Найближче заняття")
        .description("Коли наступне заняття підписаного потоку.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct CoursesWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextSessionWidget()
    }
}
