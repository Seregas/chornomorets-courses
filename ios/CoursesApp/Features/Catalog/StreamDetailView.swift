import SwiftUI

@MainActor
@Observable
final class StreamDetailViewModel {
    var state: LoadState<StreamDetail> = .loading
    var isSubscribed = false
    var working = false
    var types: [MaterialType] = []
    var announcements: [Announcement] = []
    var application: Application?

    var current: StreamDetail? { if case .loaded(let s) = state { return s } else { return nil } }

    func load(_ repo: CourseRepository, id: String) async {
        do {
            async let detail = repo.stream(id: id)
            async let subs = repo.subscriptions()
            async let t = repo.materialTypes()
            async let ann = repo.announcements(streamId: id)
            async let app = repo.application(streamId: id)
            let (d, s) = try await (detail, subs)
            isSubscribed = s.contains { $0.id == id }
            types = (try? await t) ?? []
            announcements = (try? await ann) ?? []
            application = try? await app
            state = .loaded(d)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func toggle(_ repo: CourseRepository, notifications: NotificationScheduler, detail: StreamDetail) async {
        working = true
        defer { working = false }
        do {
            if isSubscribed {
                try await repo.unsubscribe(streamId: detail.id)
                notifications.cancelReminders(streamId: detail.id)
                isSubscribed = false
            } else {
                try await repo.subscribe(streamId: detail.id)
                notifications.scheduleReminders(
                    streamId: detail.id, courseTitle: detail.title,
                    sessions: detail.sessions.map(\.session))
                isSubscribed = true
            }
        } catch { /* лишаємо попередній стан */ }
    }
}

private enum StreamSheet: Identifiable {
    case editStream, cloneStream, newAnnouncement, newSession, sessionsBatch,
         editSession(String), newMaterial, editMaterial(String), apply, applications
    var id: String {
        switch self {
        case .editStream: return "es"
        case .cloneStream: return "cs"
        case .newAnnouncement: return "na"
        case .apply: return "ap"
        case .applications: return "aps"
        case .sessionsBatch: return "sb"
        case .newSession: return "nss"
        case .editSession(let id): return "ess-\(id)"
        case .newMaterial: return "nm"
        case .editMaterial(let id): return "em-\(id)"
        }
    }
}

struct StreamDetailView: View {
    let streamId: String
    @Environment(\.repository) private var repo
    @Environment(\.notifications) private var notifications
    @Environment(\.openURL) private var openURL
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var vm = StreamDetailViewModel()
    @State private var sheet: StreamSheet?
    @State private var showExtras = false
    @State private var showFullDescription = false
    @State private var openSession: SessionWithMaterials?

    private func reload() async { await vm.load(repo, id: streamId) }

    var body: some View {
        LoadStateView(state: vm.state, retry: { Task { await vm.load(repo, id: streamId) } }) { stream in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(stream)
                    applyBlock(stream)
                    subscribeButton(stream)

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Про потік")
                        // Опис буває на пів екрана — з біографіями ведучих і
                        // розкладом. Показуємо початок, решту за запитом:
                        // інакше заняття, заради яких сюди й заходять,
                        // опиняються за межами екрана.
                        Text(stream.description)
                            .lineLimit(showFullDescription ? nil : 4)
                        if let program = stream.program, showFullDescription {
                            Text(program).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Button(showFullDescription ? "Згорнути" : "Докладніше") {
                            withAnimation { showFullDescription.toggle() }
                        }
                        .font(.subheadline)
                    }

                    if !vm.announcements.isEmpty || auth.isAdmin {
                        VStack(alignment: .leading, spacing: 10) {
                            adminSectionHeader("Оголошення") { sheet = .newAnnouncement }
                            ForEach(vm.announcements) { a in
                                announcementRow(a)
                            }
                        }
                    }

                    if !stream.materials.isEmpty || auth.isAdmin {
                        // Це матеріали курсу загалом — дошка, реквізити, спільний
                        // документ. Вони потрібні не щодня, тому за замовчуванням
                        // згорнуті: інакше десять записів занять опиняються під
                        // ними й до занять треба гортати.
                        DisclosureGroup(isExpanded: $showExtras) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(stream.materials) { m in
                                    MaterialRow(
                                        material: m,
                                        adminEdit: auth.isAdmin ? { sheet = .editMaterial(m.id) } : nil,
                                        adminDelete: auth.isAdmin ? {
                                            Task { try? await repo.deleteMaterial(id: m.id); await reload() }
                                        } : nil)
                                }
                                if auth.isAdmin {
                                    Button { sheet = .newMaterial } label: {
                                        Label("Додати матеріал", systemImage: "plus.circle")
                                            .font(.subheadline)
                                    }
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            HStack {
                                SectionHeader(title: "Додаткові матеріали")
                                Text("\(stream.materials.count)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tint(.secondary)
                    }

                    if !stream.sessions.isEmpty || auth.isAdmin {
                        VStack(alignment: .leading, spacing: 10) {
                            // Заняття додають і поштучно, і серією — тому меню, а не проста «+».
                            HStack {
                                SectionHeader(title: "Заняття")
                                Spacer()
                                if auth.isAdmin {
                                    Menu {
                                        Button { sheet = .newSession } label: {
                                            Label("Одне заняття", systemImage: "calendar.badge.plus")
                                        }
                                        Button { sheet = .sessionsBatch } label: {
                                            Label("Серія занять", systemImage: "calendar.badge.clock")
                                        }
                                    } label: { Image(systemName: "plus.circle.fill") }
                                }
                            }
                            ForEach(stream.sessions) { item in
                                NavigationLink(value: item) {
                                    SessionRow(
                                        item: item,
                                        adminEdit: auth.isAdmin ? { sheet = .editSession(item.session.id) } : nil,
                                        adminDelete: auth.isAdmin ? {
                                            Task { try? await repo.deleteSession(id: item.session.id); await reload() }
                                        } : nil)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let tg = stream.telegramGroupURL, let url = URL(string: tg) {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Телеграм-група потоку", systemImage: "paperplane.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Потік")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if auth.isAdmin {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { sheet = .editStream } label: { Label("Редагувати потік", systemImage: "pencil") }
                        Button { sheet = .cloneStream } label: {
                            Label("Клонувати потік", systemImage: "doc.on.doc")
                        }
                        Button { sheet = .applications } label: {
                            Label("Заявки", systemImage: "person.badge.clock")
                        }
                        Button(role: .destructive) {
                            Task { try? await repo.deleteStream(id: streamId); dismiss() }
                        } label: { Label("Видалити потік", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .editStream:
                if let s = vm.current {
                    StreamFormView(courseId: s.courseId, existing: s) { await reload() }
                }
            case .cloneStream:
                if let s = vm.current {
                    CloneStreamFormView(source: s) { await reload() }
                }
            case .apply:
                if let s = vm.current {
                    ApplyView(stream: s, existing: vm.application) { await reload() }
                }
            case .applications:
                ApplicationsView(streamId: streamId)
            case .newAnnouncement:
                AnnouncementFormView(streamId: streamId) { await reload() }
            case .newSession:
                SessionFormView(streamId: streamId, existing: nil) { await reload() }
            case .sessionsBatch:
                SessionsBatchFormView(streamId: streamId) { await reload() }
            case .editSession(let id):
                SessionFormView(
                    streamId: streamId,
                    existing: vm.current?.sessions.first { $0.session.id == id }?.session) { await reload() }
            case .newMaterial:
                MaterialFormView(ownerType: "stream", ownerId: streamId, editingId: nil,
                                 types: vm.types) { await reload() }
            case .editMaterial(let id):
                MaterialFormView(ownerType: "stream", ownerId: streamId, editingId: id,
                                 types: vm.types) { await reload() }
            }
        }
        .navigationDestination(for: SessionWithMaterials.self) { item in
            SessionDetailView(item: item, types: vm.types) { await reload() }
        }
        .navigationDestination(item: $openSession) { item in
            SessionDetailView(item: item, types: vm.types) { await reload() }
        }
        .task {
            await vm.load(repo, id: streamId)
            // Демо/скриншоти: одразу відкрити потрібне заняття.
            if let wanted = ProcessInfo.processInfo.environment["OPEN_SESSION"] {
                openSession = vm.current?.sessions.first { $0.session.id == wanted }
            }
        }
    }

    private func announcementRow(_ a: Announcement) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "megaphone.fill").foregroundStyle(.orange).font(.caption)
                Text(Fmt.dayTime(a.createdAt)).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if auth.isAdmin {
                    Button(role: .destructive) {
                        Task { try? await repo.deleteAnnouncement(id: a.id); await reload() }
                    } label: {
                        Image(systemName: "trash").font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(a.text).font(.subheadline)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func adminSectionHeader(_ title: String, add: @escaping () -> Void) -> some View {
        HStack {
            SectionHeader(title: title)
            Spacer()
            if auth.isAdmin {
                Button(action: add) { Image(systemName: "plus.circle.fill") }
            }
        }
    }

    private func header(_ stream: StreamDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(stream.title).font(.title2.bold())
                StatusBadge(status: stream.status)
            }
            if let date = stream.startDate {
                Text(date).foregroundStyle(.secondary)
            }
            if let price = Fmt.price(stream.priceFull, perSession: stream.pricePerSession) {
                Text(price).font(.headline)
            }
        }
    }

    /// Для майбутнього потоку головна дія — записатися (заявка), а не «підписатися».
    /// Підписка лишається способом стежити за потоком, на який ти вже ходиш.
    @ViewBuilder private func applyBlock(_ stream: StreamDetail) -> some View {
        if stream.status != .finished {
            if let app = vm.application {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.sea)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Заявку надіслано").font(.subheadline.weight(.medium))
                        Text(app.status.label).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Змінити") { sheet = .apply }.font(.caption)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            } else {
                Button { sheet = .apply } label: {
                    Label("Записатися на потік", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.sea)
            }
        }
    }

    /// Підписка — це «стежити»: розклад і нагадування. Коли поруч є заявка,
    /// вона головна дія, а підписка стає другорядною кнопкою — інакше дві
    /// однакові зелені кнопки поруч змушують гадати, яку тиснути.
    @ViewBuilder private func subscribeButton(_ stream: StreamDetail) -> some View {
        let secondary = stream.status != .finished
        let title = vm.isSubscribed
            ? "Не стежити"
            : (secondary ? "Стежити за розкладом" : "Підписатися")

        if secondary {
            Button { toggleSubscription(stream) } label: {
                label(title).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(vm.isSubscribed ? .red : .sea)
            .disabled(vm.working)
        } else {
            Button { toggleSubscription(stream) } label: {
                label(title).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(vm.isSubscribed ? .red : .sea)
            .disabled(vm.working)
        }
    }

    private func toggleSubscription(_ stream: StreamDetail) {
        Task { await vm.toggle(repo, notifications: notifications, detail: stream) }
    }

    private func label(_ title: String) -> some View {
        HStack {
            if vm.working { ProgressView() }
            Text(title)
        }
    }
}

struct SessionRow: View {
    let item: SessionWithMaterials
    var session: CourseSession { item.session }
    var adminEdit: (() -> Void)? = nil
    var adminDelete: (() -> Void)? = nil
    @Environment(\.openURL) private var openURL
    @State private var showQuestions = false
    @State private var showPulse = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title).font(.subheadline.weight(.semibold))
                Text(Fmt.dayTime(session.startAt)).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    FormatBadge(format: session.format)
                    PaymentBadge(status: session.paymentStatus)
                    // Що є в занятті — видно, не відкриваючи його.
                    SessionContentIcons(item: item)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            if let join = session.joinURL, let url = URL(string: join), isUpcoming {
                Button("Приєднатися") { openURL(url) }
                    .buttonStyle(.borderedProminent).tint(.sea).controlSize(.small)
            }
            if adminEdit != nil || adminDelete != nil {
                Menu {
                    if let adminEdit {
                        Button(action: adminEdit) { Label("Редагувати", systemImage: "pencil") }
                    }
                    if let adminDelete {
                        Button(role: .destructive, action: adminDelete) { Label("Видалити", systemImage: "trash") }
                    }
                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.secondary) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $showQuestions) {
            SessionQuestionsView(session: session)
        }
        .sheet(isPresented: $showPulse) {
            SessionPulseView(session: session)
        }
        .task {
            // Демо/скриншоти: одразу відкрити питання потрібного заняття.
            if ProcessInfo.processInfo.environment["OPEN_QUESTIONS"] == session.id {
                showQuestions = true
            }
            if ProcessInfo.processInfo.environment["OPEN_PULSE"] == session.id {
                showPulse = true
            }
        }
    }

    private var isUpcoming: Bool {
        guard let d = Fmt.date(session.startAt) else { return true }
        return d > Date()
    }
}

#Preview {
    NavigationStack { StreamDetailView(streamId: "s-stress-5") }
        .injecting(.init(repository: PreviewRepository(), notifications: NotificationScheduler()),
                   auth: AuthStore())
}
