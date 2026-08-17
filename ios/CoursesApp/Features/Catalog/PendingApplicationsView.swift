import SwiftUI

/// Усі нерозглянуті заявки з усіх потоків.
///
/// Заявки живуть на сторінці свого потоку, у меню «…» — знайти їх там можна,
/// лише якщо знаєш, що вони там є, і обійти кожен курс окремо. Людина, яка
/// подала заявку, тим часом чекає: поки викладач не поставить «зараховано»,
/// курс у неї не з'явиться. Тому список винесено на очі.
struct PendingApplicationsView: View {
    @Environment(\.repository) private var repo
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ApplicationInContext] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List {
                if loaded && items.isEmpty {
                    ContentUnavailableView(
                        "Нерозглянутих заявок немає", systemImage: "tray",
                        description: Text("Тут з'являться нові заявки на ваші потоки."))
                }
                ForEach(items) { item in
                    row(item)
                }
            }
            .navigationTitle("Заявки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
            }
            .refreshable { await load() }
        }
        .task { await load() }
    }

    @ViewBuilder private func row(_ item: ApplicationInContext) -> some View {
        let app = item.application
        VStack(alignment: .leading, spacing: 6) {
            Text(app.name).font(.subheadline.weight(.semibold))
            Text("\(item.courseTitle) · \(item.streamTitle)")
                .font(.caption).foregroundStyle(.secondary)
            Text(app.contact).font(.caption).foregroundStyle(.secondary)
            if let comment = app.comment, !comment.isEmpty {
                Text(comment).font(.caption).foregroundStyle(.secondary)
            }
            Text(Fmt.dayTime(app.createdAt)).font(.caption2).foregroundStyle(.tertiary)

            HStack(spacing: 8) {
                // «Зарахувати» — це і є той крок, після якого курс з'являється
                // в людини на екрані «Навчання»: статус enrolled підписує її
                // на потік.
                Button("Зарахувати") { Task { await setStatus(app.id, .enrolled) } }
                    .buttonStyle(.borderedProminent).tint(.sea).controlSize(.small)
                Button("Чекає оплати") { Task { await setStatus(app.id, .waitingPayment) } }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Відхилити", role: .destructive) {
                    Task { await setStatus(app.id, .declined) }
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func setStatus(_ id: String, _ status: ApplicationStatus) async {
        try? await repo.setApplicationStatus(id: id, status: status)
        await load()
    }

    private func load() async {
        items = (try? await repo.pendingApplications()) ?? []
        loaded = true
    }
}
