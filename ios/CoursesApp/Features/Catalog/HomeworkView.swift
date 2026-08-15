import SwiftUI

@MainActor
@Observable
final class HomeworkViewModel {
    var mine: Submission?
    var all: [Submission] = []
    var draft = ""
    var saving = false
    var loaded = false
    var error: String?

    func load(_ repo: CourseRepository, materialId: String, isAdmin: Bool) async {
        mine = try? await repo.submission(materialId: materialId)
        draft = mine?.text ?? ""
        if isAdmin { all = (try? await repo.submissions(materialId: materialId)) ?? [] }
        loaded = true
    }

    func submit(_ repo: CourseRepository, materialId: String, isAdmin: Bool) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        saving = true
        defer { saving = false }
        do {
            try await repo.submitHomework(materialId: materialId, text: text)
            await load(repo, materialId: materialId, isAdmin: isAdmin)
        } catch { self.error = error.localizedDescription }
    }
}

/// Домашка: завдання, поле для відповіді й рецензія викладача.
/// Повторна здача переписує свою відповідь — домашку доробляють, а не подають удруге.
struct HomeworkView: View {
    let material: MaterialDTO
    @Environment(\.repository) private var repo
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var vm = HomeworkViewModel()

    var body: some View {
        NavigationStack {
            Form {
                taskSection
                if auth.isAdmin { adminSection } else { mySection }
            }
            .navigationTitle("Домашнє завдання")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
            }
        }
        .task { await vm.load(repo, materialId: material.id, isAdmin: auth.isAdmin) }
    }

    private var taskSection: some View {
        Section("Завдання") {
            Text(material.title).font(.subheadline.weight(.medium))
            if let desc = material.description, !desc.isEmpty {
                Text(desc).font(.subheadline).foregroundStyle(.secondary)
            }
            if let due = material.dueAt {
                Label("до \(Fmt.dayTime(due))", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle((Fmt.date(due) ?? .distantFuture) < Date() ? .red : .orange)
            }
        }
    }

    // MARK: - Студент

    @ViewBuilder private var mySection: some View {
        Section {
            TextField("Ваша відповідь…", text: $vm.draft, axis: .vertical)
                .lineLimit(4...12)
        } header: {
            Text(vm.mine == nil ? "Ваша відповідь" : "Здано \(Fmt.dayTime(vm.mine!.submittedAt))")
        } footer: {
            Text("Відповідь бачить лише викладач. Можна переписати — збережеться остання.")
        }

        Section {
            if vm.saving {
                ProgressView()
            } else {
                Button(vm.mine == nil ? "Здати" : "Оновити відповідь") {
                    Task { await vm.submit(repo, materialId: material.id, isAdmin: false) }
                }
                .disabled(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let error = vm.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }

        if let feedback = vm.mine?.feedback, !feedback.isEmpty {
            Section("Відповідь викладача") {
                Text(feedback).font(.subheadline)
            }
        }
    }

    // MARK: - Викладач

    @ViewBuilder private var adminSection: some View {
        Section("Здано (\(vm.all.count))") {
            if vm.loaded && vm.all.isEmpty {
                Text("Поки ніхто не здав.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(vm.all) { s in
                NavigationLink {
                    SubmissionReviewView(submission: s) {
                        await vm.load(repo, materialId: material.id, isAdmin: true)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.authorEmail ?? s.deviceId)
                            .font(.caption).foregroundStyle(.secondary)
                        Text(s.text).font(.subheadline).lineLimit(2)
                        if s.feedback != nil {
                            Label("є відповідь", systemImage: "checkmark.bubble")
                                .font(.caption2).foregroundStyle(.green)
                        }
                    }
                }
            }
        }
    }
}

/// Рецензія на конкретну здачу.
struct SubmissionReviewView: View {
    let submission: Submission
    let onDone: () async -> Void
    @Environment(\.repository) private var repo
    @Environment(\.dismiss) private var dismiss
    @State private var feedback: String
    @State private var saving = false
    @State private var error: String?

    init(submission: Submission, onDone: @escaping () async -> Void) {
        self.submission = submission
        self.onDone = onDone
        _feedback = State(initialValue: submission.feedback ?? "")
    }

    var body: some View {
        Form {
            Section("Відповідь студента") {
                Text(submission.text).font(.subheadline)
                Text(Fmt.dayTime(submission.submittedAt))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Ваш коментар") {
                TextField("Що сказати?", text: $feedback, axis: .vertical)
                    .lineLimit(3...10)
                if saving {
                    ProgressView()
                } else {
                    Button("Зберегти") {
                        Task {
                            saving = true
                            defer { saving = false }
                            do {
                                try await repo.reviewSubmission(id: submission.id, feedback: feedback)
                                await onDone()
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(feedback.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
        .navigationTitle(submission.authorEmail ?? "Здача")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    HomeworkView(material: MaterialDTO(
        id: "m-s5-hw", title: "Підготовка до заняття 1", typeId: "mt-hw",
        description: "Занотуйте, у які моменти тижня втома накриває найсильніше.",
        url: nil, dueAt: "2026-08-19T17:00:00Z", order: 1,
        hasVideo: false, videoProvider: nil, durationMinutes: nil))
    .injecting(.init(repository: PreviewRepository(), notifications: NotificationScheduler()),
               auth: AuthStore())
}
