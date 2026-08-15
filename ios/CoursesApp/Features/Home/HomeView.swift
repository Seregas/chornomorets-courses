import SwiftUI

@MainActor
@Observable
final class HomeViewModel {
    var state: LoadState<HomeDigest> = .loading

    func load(_ repo: CourseRepository) async {
        do { state = .loaded(try await repo.home()) }
        catch { state = .failed(error.localizedDescription) }
    }
}

/// «Моє навчання» — екран для того, хто вже вчиться. Каталог відповідає на
/// «що взяти», а тут інші питання: коли наступне заняття, що не здано, які є
/// записи. Порожній стан веде в каталог — для нового користувача це вітрина.
struct HomeView: View {
    /// Дає порожньому стану перекинути користувача на вкладку курсів.
    let openCatalog: () -> Void

    @Environment(\.repository) private var repo
    @Environment(\.openURL) private var openURL
    @State private var vm = HomeViewModel()
    @State private var path: [Route] = []
    @State private var homeworkToOpen: MaterialDTO?

    var body: some View {
        NavigationStack(path: $path) {
            LoadStateView(state: vm.state, retry: { Task { await vm.load(repo) } }) { digest in
                if digest.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            // Оголошення — вище за все: якщо заняття перенесли,
                            // це головне, що людина має побачити, відкривши застосунок.
                            if !digest.announcements.isEmpty {
                                announcementsSection(digest.announcements)
                            }
                            if let next = digest.nextSession { nextSessionCard(next) }
                            if !digest.homework.isEmpty { homeworkSection(digest.homework) }
                            if !digest.recordings.isEmpty { recordingsSection(digest.recordings) }
                            if !digest.upcoming.isEmpty { upcomingSection(digest.upcoming) }
                        }
                        .padding(16)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("Навчання")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .course(let id): CourseDetailView(courseId: id)
                case .stream(let id): StreamDetailView(streamId: id)
                }
            }
            .refreshable { await vm.load(repo) }
            .sheet(item: $homeworkToOpen) { HomeworkView(material: $0) }
        }
        .task { await vm.load(repo) }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Тут буде ваше навчання", systemImage: "graduationcap")
        } description: {
            Text("Підпишіться на потік — і побачите найближче заняття, домашні завдання й записи.")
        } actions: {
            Button("Переглянути курси", action: openCatalog).buttonStyle(.borderedProminent).tint(.sea)
        }
    }

    // MARK: - Оголошення

    private func announcementsSection(_ items: [Announcement]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Оголошення")
            ForEach(items) { a in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "megaphone.fill").foregroundStyle(.orange)
                        Text(a.courseTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if SeenAnnouncements.isNew(a.id) {
                            Text("нове").font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        Text(Fmt.dayTime(a.createdAt)).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text(a.text).font(.subheadline)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
                .onTapGesture { path.append(.stream(a.streamId)) }
            }
        }
        // Позначаємо прочитаними лише коли стрічка вже на екрані.
        .onAppear { SeenAnnouncements.markSeen(items.map(\.id)) }
    }

    // MARK: - Найближче заняття

    private func nextSessionCard(_ item: ScheduleItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Найближче заняття")
            VStack(alignment: .leading, spacing: 10) {
                Text(Fmt.relativeDayTime(item.session.startAt))
                    .font(.title3.weight(.bold)).foregroundStyle(Color.sea)
                Text(item.session.title).font(.headline)
                Text("\(item.courseTitle) · \(item.streamTitle)")
                    .font(.subheadline).foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    FormatBadge(format: item.session.format)
                    PaymentBadge(status: item.session.paymentStatus)
                    Text("\(item.session.durationMinutes) хв")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let join = item.session.joinURL, let url = URL(string: join) {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Приєднатися", systemImage: "video.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.sea)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
            .onTapGesture { path.append(.stream(item.streamId)) }
        }
    }

    // MARK: - Домашка

    private func homeworkSection(_ items: [MaterialInContext]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Домашні завдання")
            ForEach(items) { item in
                Button {
                    // Відкриваємо здачу, а не сторінку потоку: з екрана «Навчання»
                    // домашку хочуть здати, а не почитати про курс.
                    homeworkToOpen = item.material
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.circle")
                            .font(.title3).foregroundStyle(.orange).frame(width: 26)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.material.title)
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let due = item.material.dueAt {
                                Text(dueLabel(due)).font(.caption).foregroundStyle(dueColor(due))
                            }
                            Text(item.courseTitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dueLabel(_ iso: String) -> String {
        guard let date = Fmt.date(iso) else { return "" }
        return date < Date() ? "дедлайн минув · \(Fmt.dayTime(iso))" : "до \(Fmt.relativeDayTime(iso))"
    }
    private func dueColor(_ iso: String) -> Color {
        (Fmt.date(iso) ?? .distantFuture) < Date() ? .red : .orange
    }

    // MARK: - Записи

    private func recordingsSection(_ items: [MaterialInContext]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Записи занять")
            ForEach(items) { item in
                MaterialRow(material: item.material)
            }
        }
    }

    // MARK: - Далі в розкладі

    private func upcomingSection(_ items: [ScheduleItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Далі")
            ForEach(items) { item in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Fmt.dayTime(item.session.startAt))
                            .font(.subheadline.weight(.medium))
                        Text("\(item.courseTitle) · \(item.session.title)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
                .onTapGesture { path.append(.stream(item.streamId)) }
            }
        }
    }
}

#Preview {
    HomeView(openCatalog: {})
        .injecting(.init(repository: PreviewRepository(), notifications: NotificationScheduler()),
                   auth: AuthStore())
}
