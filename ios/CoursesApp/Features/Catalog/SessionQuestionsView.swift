import SwiftUI

@MainActor
@Observable
final class SessionQuestionsViewModel {
    var state: LoadState<[Question]> = .loading
    var draft = ""
    var anonymous = false
    var sending = false
    var error: String?

    func load(_ repo: CourseRepository, sessionId: String) async {
        do { state = .loaded(try await repo.questions(sessionId: sessionId)) }
        catch { state = .from(error) }
    }

    func send(_ repo: CourseRepository, sessionId: String) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else { return }
        sending = true
        defer { sending = false }
        do {
            try await repo.ask(sessionId: sessionId, text: text, isAnonymous: anonymous)
            draft = ""
            await load(repo, sessionId: sessionId)
        } catch { self.error = error.localizedDescription }
    }
}

/// Питання до заняття: студент кидає заздалегідь, викладач розбирає на занятті.
/// У телеграм-групі такі питання тонуть між повідомленнями, тут — ні.
struct SessionQuestionsView: View {
    let session: CourseSession
    @Environment(\.repository) private var repo
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var vm = SessionQuestionsViewModel()

    private var isUpcoming: Bool { (Fmt.date(session.startAt) ?? .distantFuture) > Date() }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LoadStateView(state: vm.state, retry: { Task { await reload() } }) { items in
                    if items.isEmpty {
                        ContentUnavailableView(
                            "Питань поки немає",
                            systemImage: "questionmark.bubble",
                            description: Text(isUpcoming
                                ? "Спитайте те, що хочете розібрати на занятті."
                                : "До цього заняття питань не ставили."))
                    } else {
                        List {
                            ForEach(items) { q in row(q) }
                        }
                        .listStyle(.plain)
                    }
                }
                if isUpcoming { composer }
            }
            .navigationTitle("Питання")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
            }
        }
        .task { await reload() }
    }

    private func reload() async { await vm.load(repo, sessionId: session.id) }

    @ViewBuilder private func row(_ q: Question) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(q.text).font(.subheadline)
            HStack(spacing: 8) {
                if q.isMine {
                    Text("ваше питання").font(.caption2).foregroundStyle(Color.sea)
                }
                // Email автора приходить лише адміну — студенти бачать питання без імен.
                if let email = q.authorEmail {
                    Text(email).font(.caption2).foregroundStyle(.secondary)
                }
                if q.isAnswered {
                    Label("розібрано", systemImage: "checkmark.circle.fill")
                        .font(.caption2).foregroundStyle(.green)
                }
                Spacer()
                Text(Fmt.dayTime(q.createdAt)).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            if q.isMine || auth.isAdmin {
                Button(role: .destructive) {
                    Task { try? await repo.deleteQuestion(id: q.id); await reload() }
                } label: { Label("Видалити", systemImage: "trash") }
            }
        }
        .swipeActions(edge: .leading) {
            if auth.isAdmin {
                Button {
                    Task {
                        try? await repo.markQuestionAnswered(id: q.id, answered: !q.isAnswered)
                        await reload()
                    }
                } label: {
                    Label(q.isAnswered ? "Повернути" : "Розібрано",
                          systemImage: q.isAnswered ? "arrow.uturn.backward" : "checkmark")
                }
                .tint(.green)
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            TextField("Ваше питання до заняття…", text: $vm.draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
            HStack {
                Toggle("Анонімно", isOn: $vm.anonymous)
                    .toggleStyle(.button).font(.caption)
                Spacer()
                if vm.sending {
                    ProgressView()
                } else {
                    Button("Надіслати") { Task { await vm.send(repo, sessionId: session.id) } }
                        .buttonStyle(.borderedProminent).tint(.sea)
                        .disabled(vm.draft.trimmingCharacters(in: .whitespaces).count < 3)
                }
            }
            if let error = vm.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
    }
}

#Preview {
    SessionQuestionsView(session: CourseSession(
        id: "ses-s5-1", streamId: "s-stress-5", title: "Заняття 1",
        startAt: "2026-12-01T17:00:00Z", durationMinutes: 120, format: .online,
        joinURL: nil, order: 1))
    .injecting(.init(repository: PreviewRepository(), notifications: NotificationScheduler()),
               auth: AuthStore())
}
