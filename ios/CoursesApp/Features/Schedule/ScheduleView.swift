import SwiftUI

@MainActor
@Observable
final class ScheduleViewModel {
    var state: LoadState<[ScheduleItem]> = .loading

    func load(_ repo: CourseRepository, notifications: NotificationScheduler) async {
        do {
            let items = try await repo.schedule()
            state = .loaded(items)
            // Розклад — джерело правди для нагадувань: перенесені й скасовані заняття
            // мають одразу відображатися на запланованих нотифікаціях.
            await notifications.sync(with: items)
            WidgetSync.update(nextSession: items.first)
        } catch {
            state = .from(error)
        }
    }

    /// Групує заняття за календарним днем, зберігаючи хронологію.
    func grouped(_ items: [ScheduleItem]) -> [(header: String, items: [ScheduleItem])] {
        let cal = Calendar.current
        let buckets = Dictionary(grouping: items) { item -> Date in
            let d = Fmt.date(item.session.startAt) ?? Date.distantPast
            return cal.startOfDay(for: d)
        }
        return buckets.keys.sorted().map { day in
            (header: header(for: day),
             items: buckets[day]!.sorted { $0.session.startAt < $1.session.startAt })
        }
    }

    private func header(for day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Сьогодні" }
        if cal.isDateInTomorrow(day) { return "Завтра" }
        return Fmt.dayHeader(ISO8601DateFormatter().string(from: day))
    }
}

struct ScheduleView: View {
    @Environment(\.repository) private var repo
    @Environment(\.notifications) private var notifications
    @Environment(\.openURL) private var openURL
    @State private var vm = ScheduleViewModel()

    var body: some View {
        NavigationStack {
            LoadStateView(state: vm.state, retry: { Task { await vm.load(repo, notifications: notifications) } }) { items in
                if items.isEmpty {
                    ContentUnavailableView(
                        "Розклад порожній", systemImage: "calendar.badge.plus",
                        description: Text("Підпишіться на потік у розділі «Курси», і найближчі заняття зʼявляться тут."))
                } else {
                    List {
                        ForEach(vm.grouped(items), id: \.header) { group in
                            Section(group.header) {
                                ForEach(group.items) { item in
                                    ScheduleRow(item: item)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Розклад")
            .refreshable { await vm.load(repo, notifications: notifications) }
        }
        .task { await vm.load(repo, notifications: notifications) }
    }
}

struct ScheduleRow: View {
    let item: ScheduleItem
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(time).font(.title3.weight(.bold)).monospacedDigit()
                Text("\(item.session.durationMinutes) хв").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.session.title).font(.subheadline.weight(.semibold))
                Text("\(item.courseTitle) · \(item.streamTitle)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    FormatBadge(format: item.session.format)
                    PaymentBadge(payment: item.payment)
                }
            }
            Spacer()
            if let join = item.session.joinURL, let url = URL(string: join) {
                Button("Приєднатися") { openURL(url) }
                    .buttonStyle(.borderedProminent).tint(.sea).controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private var time: String {
        guard let d = Fmt.date(item.session.startAt) else { return "" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

#Preview {
    ScheduleView().injecting(.init(repository: PreviewRepository(), notifications: NotificationScheduler()),
                             auth: AuthStore())
}
