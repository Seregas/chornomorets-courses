import SwiftUI

@MainActor
@Observable
final class StreamDetailViewModel {
    var state: LoadState<StreamDetail> = .loading
    var isSubscribed = false
    var working = false
    var types: [MaterialType] = []

    var current: StreamDetail? { if case .loaded(let s) = state { return s } else { return nil } }

    func load(_ repo: CourseRepository, id: String) async {
        do {
            async let detail = repo.stream(id: id)
            async let subs = repo.subscriptions()
            async let t = repo.materialTypes()
            let (d, s) = try await (detail, subs)
            isSubscribed = s.contains { $0.id == id }
            types = (try? await t) ?? []
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
                    streamId: detail.id, courseTitle: detail.title, sessions: detail.sessions)
                isSubscribed = true
            }
        } catch { /* лишаємо попередній стан */ }
    }
}

private enum StreamSheet: Identifiable {
    case editStream, newSession, editSession(String), newMaterial, editMaterial(String)
    var id: String {
        switch self {
        case .editStream: return "es"
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

    private func reload() async { await vm.load(repo, id: streamId) }

    var body: some View {
        LoadStateView(state: vm.state, retry: { Task { await vm.load(repo, id: streamId) } }) { stream in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(stream)
                    subscribeButton(stream)

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Про потік")
                        Text(stream.description)
                        if let program = stream.program {
                            Text(program).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }

                    if !stream.sessions.isEmpty || auth.isAdmin {
                        VStack(alignment: .leading, spacing: 10) {
                            adminSectionHeader("Заняття") { sheet = .newSession }
                            ForEach(stream.sessions) { session in
                                SessionRow(
                                    session: session,
                                    adminEdit: auth.isAdmin ? { sheet = .editSession(session.id) } : nil,
                                    adminDelete: auth.isAdmin ? {
                                        Task { try? await repo.deleteSession(id: session.id); await reload() }
                                    } : nil)
                            }
                        }
                    }

                    if !stream.materials.isEmpty || auth.isAdmin {
                        VStack(alignment: .leading, spacing: 10) {
                            adminSectionHeader("Матеріали") { sheet = .newMaterial }
                            ForEach(stream.materials) { m in
                                MaterialRow(
                                    material: m,
                                    adminEdit: auth.isAdmin ? { sheet = .editMaterial(m.id) } : nil,
                                    adminDelete: auth.isAdmin ? {
                                        Task { try? await repo.deleteMaterial(id: m.id); await reload() }
                                    } : nil)
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
            case .newSession:
                SessionFormView(streamId: streamId, existing: nil) { await reload() }
            case .editSession(let id):
                SessionFormView(streamId: streamId,
                                existing: vm.current?.sessions.first { $0.id == id }) { await reload() }
            case .newMaterial:
                MaterialFormView(ownerType: "stream", ownerId: streamId, editingId: nil,
                                 types: vm.types) { await reload() }
            case .editMaterial(let id):
                MaterialFormView(ownerType: "stream", ownerId: streamId, editingId: id,
                                 types: vm.types) { await reload() }
            }
        }
        .task { await vm.load(repo, id: streamId) }
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

    @ViewBuilder
    private func subscribeButton(_ stream: StreamDetail) -> some View {
        Button {
            Task { await vm.toggle(repo, notifications: notifications, detail: stream) }
        } label: {
            HStack {
                if vm.working { ProgressView().tint(.white) }
                Text(vm.isSubscribed ? "Відписатися" : "Підписатися")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(vm.isSubscribed ? .red : .sea)
        .disabled(vm.working)
    }
}

struct SessionRow: View {
    let session: CourseSession
    var adminEdit: (() -> Void)? = nil
    var adminDelete: (() -> Void)? = nil
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title).font(.subheadline.weight(.semibold))
                Text(Fmt.dayTime(session.startAt)).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    FormatBadge(format: session.format)
                    PaymentBadge(status: session.paymentStatus)
                }
            }
            Spacer()
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
