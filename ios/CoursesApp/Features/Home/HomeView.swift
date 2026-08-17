import SwiftUI

@MainActor
@Observable
final class HomeViewModel {
    var state: LoadState<HomeDigest> = .loading
    /// Скільки заявок чекає на рішення викладача (лише для адміна).
    var pendingApplications = 0

    func load(_ repo: CourseRepository, isAdmin: Bool) async {
        do { state = .loaded(try await repo.home()) }
        catch { state = .from(error) }
        pendingApplications = isAdmin
            ? ((try? await repo.pendingApplications()) ?? []).count
            : 0
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
    @Environment(AuthStore.self) private var auth
    @State private var vm = HomeViewModel()
    @State private var path: [Route] = []
    @State private var homeworkToOpen: MaterialDTO?
    @State private var journal = PracticeJournal.shared
    @State private var showApplications = false

    var body: some View {
        NavigationStack(path: $path) {
            LoadStateView(state: vm.state, retry: { Task { await vm.load(repo, isAdmin: auth.isAdmin) } }) { digest in
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
                            if vm.pendingApplications > 0 { applicationsCard }
                            // Курси — вище за розклад: спершу «де я вчуся»,
                            // потім «що найближче». Курс із завершеними
                            // заняттями інакше зникав з екрана взагалі.
                            if !digest.streams.isEmpty { streamsSection(digest.streams) }
                            if let next = digest.nextSession { nextSessionCard(next) }
                            checkInCard
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
                case .journal: JournalView()
                }
            }
            .refreshable { await vm.load(repo, isAdmin: auth.isAdmin) }
            .sheet(item: $homeworkToOpen) { HomeworkView(material: $0) }
            .sheet(isPresented: $showApplications) {
                PendingApplicationsView()
            }
        }
        .task {
            await vm.load(repo, isAdmin: auth.isAdmin)
            // Демо/скриншоти: одразу відкрити щоденник.
            if ProcessInfo.processInfo.environment["OPEN_JOURNAL"] != nil, path.isEmpty {
                path = [.journal]
            }
        }
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

    // MARK: - Чек-ін стану

    /// Курси про стрес і вигорання просять стежити за станом — тому чек-ін
    /// живе тут, поруч із заняттями, а не десь у налаштуваннях.
    private var checkInCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Стан")
            Button {
                path.append(.journal)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "heart.text.square")
                        .font(.title3).foregroundStyle(Color.sea).frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        if let today = journal.todayCheckIn?.energy {
                            Text("Сьогодні: \(today)/5").font(.subheadline.weight(.medium))
                            Text("Щоденник практик").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Як ви сьогодні?").font(.subheadline.weight(.medium))
                            Text("Чек-ін за 5 секунд").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Заявки (викладачу)

    /// Заявки лежать у меню «…» кожного потоку окремо — знайти їх там можна,
    /// лише знаючи, що вони там є. А людина, яка подала заявку, до рішення
    /// викладача курсу в себе не бачить, тож затримка коштує дорого.
    private var applicationsCard: some View {
        Button {
            showApplications = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.clock")
                    .font(.title3).foregroundStyle(.orange).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(vm.pendingApplications) заявок чекають рішення")
                        .font(.subheadline.weight(.medium))
                    Text("Зарахування відкриває людині курс").font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Мої курси

    private func streamsSection(_ items: [EnrolledStream]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Мої курси")
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.courseTitle).font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    Text(item.streamTitle).font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: progress(item))
                        .tint(.sea)
                    HStack(spacing: 8) {
                        Text("\(item.sessionsPassed) з \(item.sessionsTotal) занять")
                            .font(.caption).foregroundStyle(.secondary)
                        if let next = item.nextSessionAt {
                            Text("· далі \(Fmt.relativeDayTime(next))")
                                .font(.caption).foregroundStyle(Color.sea)
                        } else {
                            Text("· курс завершено").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        // Скільки занять ще не підтверджено оплатою — те, через
                        // що студент і викладач найчастіше листуються.
                        if item.unpaidSessions > 0 {
                            Pill(text: "\(item.unpaidSessions) без оплати",
                                 fg: .orange, bg: .orange.opacity(0.15))
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
                .onTapGesture { path.append(.stream(item.streamId)) }
            }
        }
    }

    private func progress(_ item: EnrolledStream) -> Double {
        guard item.sessionsTotal > 0 else { return 0 }
        return Double(item.sessionsPassed) / Double(item.sessionsTotal)
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
                    PaymentBadge(payment: item.payment)
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
                VStack(alignment: .leading, spacing: 2) {
                    MaterialRow(material: item.material)
                    // Записи з різних курсів лежать одним списком — без назви
                    // курсу незрозуміло, чий це запис.
                    Text(item.courseTitle)
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                }
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
